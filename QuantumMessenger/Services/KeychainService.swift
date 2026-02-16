import Foundation
import CryptoKit

/// Manages secure storage of cryptographic keys using UserDefaults for demo purposes.
/// In production, you would use the iOS Keychain (SecKey) or Secure Enclave.
@available(iOS 26.0, macOS 26.0, *)
final class KeychainService {

    private static let privateKeyKey = "com.quantummessenger.privateKey"
    private static let publicKeyKey = "com.quantummessenger.publicKey"
    private static let signingPrivateKeyKey = "com.quantummessenger.signingPrivateKey"
    private static let signingPublicKeyKey = "com.quantummessenger.signingPublicKey"
    private static let contactsKey = "com.quantummessenger.contacts"
    private static let messagesKey = "com.quantummessenger.messages"

    // MARK: - Key Storage

    /// Save the user's encryption key pair
    static func saveKeyPair(
        privateKey: XWingMLKEM768X25519.PrivateKey,
        publicKey: XWingMLKEM768X25519.PublicKey
    ) throws {
        let privateKeyData = try CryptoService.exportPrivateKey(privateKey)
        let publicKeyData = CryptoService.exportPublicKey(publicKey)

        UserDefaults.standard.set(privateKeyData, forKey: privateKeyKey)
        UserDefaults.standard.set(publicKeyData, forKey: publicKeyKey)
    }

    /// Load the user's private key
    static func loadPrivateKey() -> XWingMLKEM768X25519.PrivateKey? {
        guard let data = UserDefaults.standard.data(forKey: privateKeyKey) else {
            return nil
        }
        return try? CryptoService.importPrivateKey(from: data)
    }

    /// Load the user's public key
    static func loadPublicKey() -> XWingMLKEM768X25519.PublicKey? {
        guard let data = UserDefaults.standard.data(forKey: publicKeyKey) else {
            return nil
        }
        return try? CryptoService.importPublicKey(from: data)
    }

    /// Check if an encryption key pair exists
    static func hasKeyPair() -> Bool {
        return UserDefaults.standard.data(forKey: privateKeyKey) != nil
    }

    /// Delete the stored encryption key pair
    static func deleteKeyPair() {
        UserDefaults.standard.removeObject(forKey: privateKeyKey)
        UserDefaults.standard.removeObject(forKey: publicKeyKey)
    }

    // MARK: - Signing Key Storage

    /// Save the user's signing key pair
    static func saveSigningKeyPair(
        privateKey: MLDSA65.PrivateKey,
        publicKey: MLDSA65.PublicKey
    ) throws {
        let privateKeyData = try CryptoService.exportSigningPrivateKey(privateKey)
        let publicKeyData = CryptoService.exportSigningPublicKey(publicKey)

        UserDefaults.standard.set(privateKeyData, forKey: signingPrivateKeyKey)
        UserDefaults.standard.set(publicKeyData, forKey: signingPublicKeyKey)
    }

    /// Load the user's signing private key
    static func loadSigningPrivateKey() -> MLDSA65.PrivateKey? {
        guard let data = UserDefaults.standard.data(forKey: signingPrivateKeyKey) else {
            return nil
        }
        return try? CryptoService.importSigningPrivateKey(from: data)
    }

    /// Load the user's signing public key
    static func loadSigningPublicKey() -> MLDSA65.PublicKey? {
        guard let data = UserDefaults.standard.data(forKey: signingPublicKeyKey) else {
            return nil
        }
        return try? CryptoService.importSigningPublicKey(from: data)
    }

    /// Check if a signing key pair exists
    static func hasSigningKeyPair() -> Bool {
        return UserDefaults.standard.data(forKey: signingPrivateKeyKey) != nil
    }

    /// Delete the stored signing key pair
    static func deleteSigningKeyPair() {
        UserDefaults.standard.removeObject(forKey: signingPrivateKeyKey)
        UserDefaults.standard.removeObject(forKey: signingPublicKeyKey)
    }

    // MARK: - Contact Storage

    /// Save contacts list
    static func saveContacts(_ contacts: [Contact]) {
        if let data = try? JSONEncoder().encode(contacts) {
            UserDefaults.standard.set(data, forKey: contactsKey)
        }
    }

    /// Load contacts list
    static func loadContacts() -> [Contact] {
        guard let data = UserDefaults.standard.data(forKey: contactsKey),
              let contacts = try? JSONDecoder().decode([Contact].self, from: data) else {
            return []
        }
        return contacts
    }

    // MARK: - Message Storage

    /// Save messages list
    static func saveMessages(_ messages: [EncryptedMessage]) {
        if let data = try? JSONEncoder().encode(messages) {
            UserDefaults.standard.set(data, forKey: messagesKey)
        }
    }

    /// Load messages list
    static func loadMessages() -> [EncryptedMessage] {
        guard let data = UserDefaults.standard.data(forKey: messagesKey),
              let messages = try? JSONDecoder().decode([EncryptedMessage].self, from: data) else {
            return []
        }
        return messages
    }
}
