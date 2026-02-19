import Foundation
import CryptoKit
import SwiftUI

/// Central app state managing keys, contacts, and messages
@available(iOS 26.0, macOS 26.0, *)
@Observable
final class AppState {

    // MARK: - Properties

    var privateKey: XWingMLKEM768X25519.PrivateKey?
    var publicKey: XWingMLKEM768X25519.PublicKey?
    var signingPrivateKey: MLDSA65.PrivateKey?
    var signingPublicKey: MLDSA65.PublicKey?
    var contacts: [Contact] = []
    var messages: [EncryptedMessage] = []
    var errorMessage: String?
    var showError: Bool = false

    // MARK: - User Identity

    var userName: String = "" {
        didSet { UserDefaults.standard.set(userName, forKey: "com.quantummessenger.userName") }
    }
    var userEmail: String = "" {
        didSet { UserDefaults.standard.set(userEmail, forKey: "com.quantummessenger.userEmail") }
    }
    var keyCreatedAt: Date? = nil {
        didSet {
            if let d = keyCreatedAt {
                UserDefaults.standard.set(d.timeIntervalSince1970, forKey: "com.quantummessenger.keyCreatedAt")
            } else {
                UserDefaults.standard.removeObject(forKey: "com.quantummessenger.keyCreatedAt")
            }
        }
    }

    /// Formatted "Name <email>" string for key headers
    var userId: String {
        let n = userName.trimmingCharacters(in: .whitespaces)
        let e = userEmail.trimmingCharacters(in: .whitespaces)
        if n.isEmpty && e.isEmpty { return "QuantumMessenger User" }
        if e.isEmpty { return n }
        return "\(n) <\(e)>"
    }

    /// Formatted key creation date
    var keyCreatedAtFormatted: String {
        guard let date = keyCreatedAt else { return "Unknown" }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    var hasKeyPair: Bool {
        privateKey != nil && publicKey != nil
    }

    var hasSigningKeyPair: Bool {
        signingPrivateKey != nil && signingPublicKey != nil
    }

    var hasAllKeys: Bool {
        hasKeyPair && hasSigningKeyPair
    }

    /// Public key as a Base64 string for sharing
    var publicKeyBase64: String? {
        guard let publicKey else { return nil }
        return CryptoService.exportPublicKey(publicKey).base64EncodedString()
    }

    /// Signing public key as a Base64 string for sharing
    var signingPublicKeyBase64: String? {
        guard let signingPublicKey else { return nil }
        return CryptoService.exportSigningPublicKey(signingPublicKey).base64EncodedString()
    }

    // MARK: - Initialization

    init() {
        loadStoredData()
    }

    // MARK: - Key Management

    /// Generate new encryption and signing key pairs
    func generateNewKeyPair() {
        do {
            // Generate encryption keys
            let (sk, pk) = try CryptoService.generateKeyPair()
            self.privateKey = sk
            self.publicKey = pk
            try KeychainService.saveKeyPair(privateKey: sk, publicKey: pk)

            // Generate signing keys
            let (sigSk, sigPk) = try CryptoService.generateSigningKeyPair()
            self.signingPrivateKey = sigSk
            self.signingPublicKey = sigPk
            try KeychainService.saveSigningKeyPair(privateKey: sigSk, publicKey: sigPk)

            // Record creation time
            keyCreatedAt = Date()
        } catch {
            setError("Key generation failed: \(error.localizedDescription)")
        }
    }

    /// Delete existing key pairs
    func deleteKeyPair() {
        privateKey = nil
        publicKey = nil
        signingPrivateKey = nil
        signingPublicKey = nil
        keyCreatedAt = nil
        KeychainService.deleteKeyPair()
        KeychainService.deleteSigningKeyPair()
    }

    // MARK: - Contacts

    /// Add a contact from Base64-encoded public keys
    func addContact(name: String, publicKeyBase64: String, signingPublicKeyBase64: String? = nil) {
        guard let keyData = Data(base64Encoded: publicKeyBase64) else {
            setError("Invalid public key format. Expected Base64-encoded data.")
            return
        }

        var signingKeyData: Data? = nil
        if let signingKey64 = signingPublicKeyBase64, !signingKey64.isEmpty {
            guard let data = Data(base64Encoded: signingKey64) else {
                setError("Invalid signing public key format. Expected Base64-encoded data.")
                return
            }
            signingKeyData = data
        }

        do {
            // Validate the encryption key
            _ = try CryptoService.importPublicKey(from: keyData)

            // Validate the signing key if provided
            if let signingData = signingKeyData {
                _ = try CryptoService.importSigningPublicKey(from: signingData)
            }

            let contact = Contact(name: name, publicKeyData: keyData, signingPublicKeyData: signingKeyData)
            contacts.append(contact)
            KeychainService.saveContacts(contacts)
        } catch {
            setError("Invalid public key: \(error.localizedDescription)")
        }
    }

    /// Remove a contact
    func removeContact(_ contact: Contact) {
        contacts.removeAll { $0.id == contact.id }
        KeychainService.saveContacts(contacts)
    }

    // MARK: - Messaging

    /// Encrypt and optionally sign a message to a contact
    func encryptMessage(to contact: Contact, plaintext: String, withSignature: Bool = true) -> EncryptedEnvelope? {
        do {
            let recipientKey = try CryptoService.importPublicKey(from: contact.publicKeyData)

            // Create metadata with sender info and timestamp
            let metadataDict: [String: String] = [
                "sender": "me",
                "recipient": contact.name,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
            let metadata = try JSONEncoder().encode(metadataDict)

            // If signing is requested and we have signing keys, sign the message
            if withSignature, let signingPrivateKey {
                let envelope = try CryptoService.encryptAndSign(
                    message: plaintext,
                    recipientPublicKey: recipientKey,
                    signingPrivateKey: signingPrivateKey,
                    authenticatedMetadata: metadata
                )
                return envelope
            } else {
                // Otherwise just encrypt
                let envelope = try CryptoService.encrypt(
                    message: plaintext,
                    recipientPublicKey: recipientKey,
                    authenticatedMetadata: metadata
                )
                return envelope
            }
        } catch {
            setError("Encryption failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Receive and store an encrypted message from a Base64 string
    func receiveMessage(senderName: String, base64Envelope: String) {
        do {
            let envelope = try EncryptedEnvelope.fromBase64String(base64Envelope)
            let message = EncryptedMessage(
                senderName: senderName,
                encryptedEnvelope: envelope
            )
            messages.insert(message, at: 0)
            KeychainService.saveMessages(messages)
        } catch {
            setError("Failed to receive message: \(error.localizedDescription)")
        }
    }

    /// Decrypt a received message and verify signature if present
    func decryptMessage(_ message: EncryptedMessage) {
        guard let privateKey else {
            setError("No private key available. Generate a key pair first.")
            return
        }

        do {
            var plaintext: String
            var signatureValid: Bool? = nil

            // If the message has a signature, try to verify it
            if message.isSigned {
                // Try to find the sender in contacts to get their signing public key
                let sender = contacts.first { $0.name == message.senderName }
                
                if let senderSigningKeyData = sender?.signingPublicKeyData {
                    let senderSigningKey = try CryptoService.importSigningPublicKey(from: senderSigningKeyData)
                    
                    // Decrypt and verify signature
                    plaintext = try CryptoService.decryptAndVerify(
                        envelope: message.encryptedEnvelope,
                        privateKey: privateKey,
                        senderPublicKey: senderSigningKey
                    )
                    signatureValid = true
                } else {
                    // No signing key for sender, just decrypt without verification
                    plaintext = try CryptoService.decrypt(
                        envelope: message.encryptedEnvelope,
                        privateKey: privateKey
                    )
                    signatureValid = nil // Unknown, can't verify
                }
            } else {
                // No signature present, just decrypt
                plaintext = try CryptoService.decrypt(
                    envelope: message.encryptedEnvelope,
                    privateKey: privateKey
                )
                signatureValid = nil
            }

            // Update the message with decrypted content and signature status
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index].decryptedContent = plaintext
                messages[index].signatureVerified = signatureValid
                KeychainService.saveMessages(messages)
            }
        } catch {
            setError("Decryption failed: \(error.localizedDescription)")
        }
    }

    /// Delete a message
    func deleteMessage(_ message: EncryptedMessage) {
        messages.removeAll { $0.id == message.id }
        KeychainService.saveMessages(messages)
    }

    // MARK: - Demo

    /// Run a self-test: encrypt and sign a message to ourselves, then decrypt and verify
    func runSelfTest() -> (success: Bool, detail: String) {
        guard let publicKey, let privateKey else {
            return (false, "No encryption key pair. Generate one first.")
        }

        do {
            let testMessage = "Hello, post-quantum world! 🔐"
            let metadata = "self-test".data(using: .utf8)!

            // Test with signature if we have signing keys
            if let signingPrivateKey, let signingPublicKey {
                // Encrypt and sign
                let envelope = try CryptoService.encryptAndSign(
                    message: testMessage,
                    recipientPublicKey: publicKey,
                    signingPrivateKey: signingPrivateKey,
                    authenticatedMetadata: metadata
                )

                // Decrypt and verify
                let decrypted = try CryptoService.decryptAndVerify(
                    envelope: envelope,
                    privateKey: privateKey,
                    senderPublicKey: signingPublicKey
                )

                if decrypted == testMessage {
                    return (true, """
                    ✅ Encrypted, signed, decrypted, and verified successfully!
                    
                    Original: \(testMessage)
                    Decrypted: \(decrypted)
                    
                    Encryption: XWingMLKEM768X25519 (ML-KEM-768 + X25519)
                    Signature: ML-DSA-65
                    Hash: SHA-256
                    AEAD: AES-GCM-256
                    
                    🛡️ Full post-quantum security: confidentiality AND authenticity!
                    """)
                } else {
                    return (false, "Decrypted text does not match original.")
                }
            } else {
                // Just test encryption without signing
                let envelope = try CryptoService.encrypt(
                    message: testMessage,
                    recipientPublicKey: publicKey,
                    authenticatedMetadata: metadata
                )

                let decrypted = try CryptoService.decrypt(
                    envelope: envelope,
                    privateKey: privateKey
                )

                if decrypted == testMessage {
                    return (true, """
                    Encrypted and decrypted successfully.
                    
                    Original: \(testMessage)
                    Decrypted: \(decrypted)
                    Ciphersuite: XWingMLKEM768X25519_SHA256_AES_GCM_256
                    
                    Note: Generate signing keys for full authentication support.
                    """)
                } else {
                    return (false, "Decrypted text does not match original.")
                }
            }
        } catch {
            return (false, "Self-test failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    private func loadStoredData() {
        privateKey = KeychainService.loadPrivateKey()
        publicKey = KeychainService.loadPublicKey()
        signingPrivateKey = KeychainService.loadSigningPrivateKey()
        signingPublicKey = KeychainService.loadSigningPublicKey()
        contacts = KeychainService.loadContacts()
        messages = KeychainService.loadMessages()
        userName = UserDefaults.standard.string(forKey: "com.quantummessenger.userName") ?? ""
        userEmail = UserDefaults.standard.string(forKey: "com.quantummessenger.userEmail") ?? ""
        if let ts = UserDefaults.standard.object(forKey: "com.quantummessenger.keyCreatedAt") as? Double {
            keyCreatedAt = Date(timeIntervalSince1970: ts)
        }
    }

    private func setError(_ message: String) {
        errorMessage = message
        showError = true
    }
}
