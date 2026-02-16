import Foundation
import CryptoKit

// MARK: - Post-Quantum Encrypted Messaging Service
// Uses XWingMLKEM768X25519 via HPKE (Hybrid Public Key Encryption)
// Provides quantum-resistant encryption combining ML-KEM-768 + X25519

/// Errors that can occur during cryptographic operations
enum CryptoError: LocalizedError {
    case keyGenerationFailed
    case encryptionFailed(String)
    case decryptionFailed(String)
    case invalidPublicKeyData
    case invalidPrivateKeyData
    case invalidMessageFormat
    case signingFailed(String)
    case verificationFailed(String)
    case invalidSignatureData

    var errorDescription: String? {
        switch self {
        case .keyGenerationFailed:
            return "Failed to generate key pair"
        case .encryptionFailed(let detail):
            return "Encryption failed: \(detail)"
        case .decryptionFailed(let detail):
            return "Decryption failed: \(detail)"
        case .invalidPublicKeyData:
            return "Invalid public key data"
        case .invalidPrivateKeyData:
            return "Invalid private key data"
        case .invalidMessageFormat:
            return "Invalid encrypted message format"
        case .signingFailed(let detail):
            return "Signing failed: \(detail)"
        case .verificationFailed(let detail):
            return "Signature verification failed: \(detail)"
        case .invalidSignatureData:
            return "Invalid signature data"
        }
    }
}

/// Result of encrypting a message, containing all data needed for decryption
struct EncryptedEnvelope: Codable {
    /// The HPKE encapsulated key (needed by recipient to derive shared secret)
    let encapsulatedKey: Data
    /// The encrypted ciphertext
    let ciphertext: Data
    /// Additional authenticated data (metadata) used during encryption
    let metadata: Data
    /// Human-readable description of the encryption scheme
    let scheme: String
    /// Optional digital signature (ML-DSA-65) of the ciphertext for sender authentication
    let signature: Data?

    init(encapsulatedKey: Data, ciphertext: Data, metadata: Data, signature: Data? = nil) {
        self.encapsulatedKey = encapsulatedKey
        self.ciphertext = ciphertext
        self.metadata = metadata
        self.scheme = "XWingMLKEM768X25519_SHA256_AES_GCM_256"
        self.signature = signature
    }

    /// Serialize the envelope to JSON Data for transmission
    func serialized() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return try encoder.encode(self)
    }

    /// Deserialize an envelope from JSON Data
    static func deserialize(from data: Data) throws -> EncryptedEnvelope {
        let decoder = JSONDecoder()
        return try decoder.decode(EncryptedEnvelope.self, from: data)
    }

    /// Serialize to a Base64 string for easy sharing
    func toBase64String() throws -> String {
        let data = try serialized()
        return data.base64EncodedString()
    }

    /// Deserialize from a Base64 string
    static func fromBase64String(_ string: String) throws -> EncryptedEnvelope {
        guard let data = Data(base64Encoded: string) else {
            throw CryptoError.invalidMessageFormat
        }
        return try deserialize(from: data)
    }
}

/// Service handling all post-quantum cryptographic operations
/// Uses Apple CryptoKit's XWingMLKEM768X25519 HPKE ciphersuite
@available(iOS 26.0, macOS 26.0, *)
final class CryptoService {

    // MARK: - HPKE Ciphersuite

    /// The post-quantum hybrid HPKE ciphersuite:
    /// - KEM: X-Wing (ML-KEM-768 + X25519)
    /// - KDF: HKDF-SHA256
    /// - AEAD: AES-GCM-256
    static let ciphersuite = HPKE.Ciphersuite.XWingMLKEM768X25519_SHA256_AES_GCM_256

    // MARK: - Key Generation

    /// Generate a new X-Wing key pair for receiving encrypted messages
    /// - Returns: A tuple of (privateKey, publicKey)
    static func generateKeyPair() throws -> (
        privateKey: XWingMLKEM768X25519.PrivateKey,
        publicKey: XWingMLKEM768X25519.PublicKey
    ) {
        do {
            let privateKey = try XWingMLKEM768X25519.PrivateKey()
            let publicKey = privateKey.publicKey
            return (privateKey, publicKey)
        } catch {
            throw CryptoError.keyGenerationFailed
        }
    }

    // MARK: - Encryption (Sender Side)

    /// Encrypt a message using the recipient's public key
    /// - Parameters:
    ///   - message: The plaintext message string to encrypt
    ///   - recipientPublicKey: The recipient's X-Wing public key
    ///   - authenticatedMetadata: Optional metadata to authenticate (not encrypted, but tamper-proof)
    /// - Returns: An EncryptedEnvelope containing all data needed for decryption
    static func encrypt(
        message: String,
        recipientPublicKey: XWingMLKEM768X25519.PublicKey,
        authenticatedMetadata: Data = Data()
    ) throws -> EncryptedEnvelope {
        guard let messageData = message.data(using: .utf8) else {
            throw CryptoError.encryptionFailed("Could not encode message as UTF-8")
        }

        return try encrypt(
            data: messageData,
            recipientPublicKey: recipientPublicKey,
            authenticatedMetadata: authenticatedMetadata
        )
    }

    /// Encrypt raw data using the recipient's public key
    /// - Parameters:
    ///   - data: The plaintext data to encrypt
    ///   - recipientPublicKey: The recipient's X-Wing public key
    ///   - authenticatedMetadata: Optional metadata to authenticate
    /// - Returns: An EncryptedEnvelope containing all data needed for decryption
    static func encrypt(
        data: Data,
        recipientPublicKey: XWingMLKEM768X25519.PublicKey,
        authenticatedMetadata: Data = Data()
    ) throws -> EncryptedEnvelope {
        do {
            // Create HPKE sender with the recipient's public key
            // This performs the X-Wing key encapsulation internally
            var sender = try HPKE.Sender(
                recipientKey: recipientPublicKey,
                ciphersuite: ciphersuite,
                info: Data() // Application-specific info (optional context binding)
            )

            // Seal (encrypt + authenticate) the message data
            // The metadata is authenticated but NOT encrypted
            let ciphertext = try sender.seal(
                data,
                authenticating: authenticatedMetadata
            )

            // Package everything the recipient needs into an envelope
            return EncryptedEnvelope(
                encapsulatedKey: sender.encapsulatedKey,
                ciphertext: ciphertext,
                metadata: authenticatedMetadata
            )
        } catch {
            throw CryptoError.encryptionFailed(error.localizedDescription)
        }
    }

    // MARK: - Decryption (Recipient Side)

    /// Decrypt an encrypted envelope using the recipient's private key
    /// - Parameters:
    ///   - envelope: The EncryptedEnvelope received from the sender
    ///   - privateKey: The recipient's X-Wing private key
    /// - Returns: The decrypted message string
    static func decrypt(
        envelope: EncryptedEnvelope,
        privateKey: XWingMLKEM768X25519.PrivateKey
    ) throws -> String {
        let data = try decryptData(envelope: envelope, privateKey: privateKey)
        guard let message = String(data: data, encoding: .utf8) else {
            throw CryptoError.decryptionFailed("Could not decode decrypted data as UTF-8")
        }
        return message
    }

    /// Decrypt an encrypted envelope to raw data using the recipient's private key
    /// - Parameters:
    ///   - envelope: The EncryptedEnvelope received from the sender
    ///   - privateKey: The recipient's X-Wing private key
    /// - Returns: The decrypted data
    static func decryptData(
        envelope: EncryptedEnvelope,
        privateKey: XWingMLKEM768X25519.PrivateKey
    ) throws -> Data {
        do {
            // Create HPKE recipient using our private key and the sender's encapsulated key
            // This performs X-Wing key decapsulation internally
            var recipient = try HPKE.Recipient(
                privateKey: privateKey,
                ciphersuite: ciphersuite,
                info: Data(), // Must match the info used during encryption
                encapsulatedKey: envelope.encapsulatedKey
            )

            // Open (decrypt + verify) the ciphertext
            // The metadata is verified against what the sender authenticated
            let decryptedData = try recipient.open(
                envelope.ciphertext,
                authenticating: envelope.metadata
            )

            return decryptedData
        } catch {
            throw CryptoError.decryptionFailed(error.localizedDescription)
        }
    }

    // MARK: - Key Serialization

    /// Export a public key to raw bytes for sharing with others
    static func exportPublicKey(_ publicKey: XWingMLKEM768X25519.PublicKey) -> Data {
        return publicKey.rawRepresentation
    }

    /// Import a public key from raw bytes received from someone else
    static func importPublicKey(from data: Data) throws -> XWingMLKEM768X25519.PublicKey {
        do {
            return try XWingMLKEM768X25519.PublicKey(rawRepresentation: data)
        } catch {
            throw CryptoError.invalidPublicKeyData
        }
    }

    /// Export a private key to secure bytes for storage (includes integrity checking)
    static func exportPrivateKey(_ privateKey: XWingMLKEM768X25519.PrivateKey) throws -> Data {
        return try privateKey.integrityCheckedRepresentation
    }

    /// Import a private key from secure bytes with integrity checking
    static func importPrivateKey(from data: Data) throws -> XWingMLKEM768X25519.PrivateKey {
        do {
            return try XWingMLKEM768X25519.PrivateKey(integrityCheckedRepresentation: data)
        } catch {
            throw CryptoError.invalidPrivateKeyData
        }
    }

    // MARK: - Digital Signatures (Post-Quantum)

    /// Generate a new ML-DSA-65 signing key pair
    /// - Returns: A tuple of (privateKey, publicKey)
    static func generateSigningKeyPair() throws -> (
        privateKey: MLDSA65.PrivateKey,
        publicKey: MLDSA65.PublicKey
    ) {
        do {
            let privateKey = try MLDSA65.PrivateKey()
            let publicKey = privateKey.publicKey
            return (privateKey, publicKey)
        } catch {
            throw CryptoError.keyGenerationFailed
        }
    }

    /// Sign a message with a signing private key
    /// - Parameters:
    ///   - message: The message string to sign
    ///   - privateKey: The ML-DSA-65 private key
    /// - Returns: The signature data
    static func sign(message: String, with privateKey: MLDSA65.PrivateKey) throws -> Data {
        guard let messageData = message.data(using: .utf8) else {
            throw CryptoError.signingFailed("Could not encode message as UTF-8")
        }
        return try sign(data: messageData, with: privateKey)
    }

    /// Sign raw data with a signing private key
    /// - Parameters:
    ///   - data: The data to sign
    ///   - privateKey: The ML-DSA-65 private key
    /// - Returns: The signature data
    static func sign(data: Data, with privateKey: MLDSA65.PrivateKey) throws -> Data {
        do {
            let signature = try privateKey.signature(for: data)
            return signature
        } catch {
            throw CryptoError.signingFailed(error.localizedDescription)
        }
    }

    /// Verify a signature on a message
    /// - Parameters:
    ///   - message: The message string that was signed
    ///   - signature: The signature data
    ///   - publicKey: The ML-DSA-65 public key
    /// - Returns: True if the signature is valid, false otherwise
    static func verify(message: String, signature: Data, with publicKey: MLDSA65.PublicKey) throws -> Bool {
        guard let messageData = message.data(using: .utf8) else {
            throw CryptoError.verificationFailed("Could not encode message as UTF-8")
        }
        return try verify(data: messageData, signature: signature, with: publicKey)
    }

    /// Verify a signature on raw data
    /// - Parameters:
    ///   - data: The data that was signed
    ///   - signature: The signature data
    ///   - publicKey: The ML-DSA-65 public key
    /// - Returns: True if the signature is valid, false otherwise
    static func verify(data: Data, signature: Data, with publicKey: MLDSA65.PublicKey) throws -> Bool {
        do {
            return try publicKey.isValidSignature(signature, for: data)
        } catch {
            throw CryptoError.verificationFailed(error.localizedDescription)
        }
    }

    // MARK: - Signature Key Serialization

    /// Export a signing public key to raw bytes for sharing
    static func exportSigningPublicKey(_ publicKey: MLDSA65.PublicKey) -> Data {
        return publicKey.rawRepresentation
    }

    /// Import a signing public key from raw bytes
    static func importSigningPublicKey(from data: Data) throws -> MLDSA65.PublicKey {
        do {
            return try MLDSA65.PublicKey(rawRepresentation: data)
        } catch {
            throw CryptoError.invalidPublicKeyData
        }
    }

    /// Export a signing private key to secure bytes for storage
    static func exportSigningPrivateKey(_ privateKey: MLDSA65.PrivateKey) throws -> Data {
        return try privateKey.integrityCheckedRepresentation
    }

    /// Import a signing private key from secure bytes
    static func importSigningPrivateKey(from data: Data) throws -> MLDSA65.PrivateKey {
        do {
            return try MLDSA65.PrivateKey(integrityCheckedRepresentation: data)
        } catch {
            throw CryptoError.invalidPrivateKeyData
        }
    }

    // MARK: - Convenience

    /// Encrypt a message and return it as a Base64 string ready for transmission
    static func encryptToBase64(
        message: String,
        recipientPublicKey: XWingMLKEM768X25519.PublicKey,
        authenticatedMetadata: Data = Data()
    ) throws -> String {
        let envelope = try encrypt(
            message: message,
            recipientPublicKey: recipientPublicKey,
            authenticatedMetadata: authenticatedMetadata
        )
        return try envelope.toBase64String()
    }

    /// Decrypt a message from a Base64 encoded envelope string
    static func decryptFromBase64(
        base64String: String,
        privateKey: XWingMLKEM768X25519.PrivateKey
    ) throws -> String {
        let envelope = try EncryptedEnvelope.fromBase64String(base64String)
        return try decrypt(envelope: envelope, privateKey: privateKey)
    }

    /// Encrypt AND sign a message for maximum security
    /// - Parameters:
    ///   - message: The plaintext message to encrypt and sign
    ///   - recipientPublicKey: The recipient's encryption public key
    ///   - signingPrivateKey: The sender's signing private key
    ///   - authenticatedMetadata: Optional metadata
    /// - Returns: An EncryptedEnvelope with signature included
    static func encryptAndSign(
        message: String,
        recipientPublicKey: XWingMLKEM768X25519.PublicKey,
        signingPrivateKey: MLDSA65.PrivateKey,
        authenticatedMetadata: Data = Data()
    ) throws -> EncryptedEnvelope {
        // First encrypt the message
        let envelope = try encrypt(
            message: message,
            recipientPublicKey: recipientPublicKey,
            authenticatedMetadata: authenticatedMetadata
        )

        // Then sign the ciphertext (proves sender identity)
        let signature = try sign(data: envelope.ciphertext, with: signingPrivateKey)

        // Create a new envelope with the signature included
        return EncryptedEnvelope(
            encapsulatedKey: envelope.encapsulatedKey,
            ciphertext: envelope.ciphertext,
            metadata: envelope.metadata,
            signature: signature
        )
    }

    /// Decrypt and verify signature on a message
    /// - Parameters:
    ///   - envelope: The encrypted and signed envelope
    ///   - privateKey: The recipient's decryption private key
    ///   - senderPublicKey: The sender's signing public key
    /// - Returns: The decrypted message (only if signature is valid)
    /// - Throws: CryptoError if decryption fails or signature is invalid
    static func decryptAndVerify(
        envelope: EncryptedEnvelope,
        privateKey: XWingMLKEM768X25519.PrivateKey,
        senderPublicKey: MLDSA65.PublicKey
    ) throws -> String {
        // Verify signature first (fail fast if tampered)
        guard let signature = envelope.signature else {
            throw CryptoError.verificationFailed("No signature present in envelope")
        }

        let isValid = try verify(data: envelope.ciphertext, signature: signature, with: senderPublicKey)
        guard isValid else {
            throw CryptoError.verificationFailed("Signature verification failed - message may be tampered or from wrong sender")
        }

        // If signature is valid, decrypt the message
        return try decrypt(envelope: envelope, privateKey: privateKey)
    }
}
