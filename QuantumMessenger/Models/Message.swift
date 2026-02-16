import Foundation

/// Represents an encrypted message in the app
struct EncryptedMessage: Identifiable, Codable {
    let id: UUID
    let senderName: String
    let timestamp: Date
    let encryptedEnvelope: EncryptedEnvelope
    var decryptedContent: String?
    var signatureVerified: Bool?
    var isDecrypted: Bool { decryptedContent != nil }
    var isSigned: Bool { encryptedEnvelope.signature != nil }

    init(
        id: UUID = UUID(),
        senderName: String,
        timestamp: Date = Date(),
        encryptedEnvelope: EncryptedEnvelope,
        decryptedContent: String? = nil,
        signatureVerified: Bool? = nil
    ) {
        self.id = id
        self.senderName = senderName
        self.timestamp = timestamp
        self.encryptedEnvelope = encryptedEnvelope
        self.decryptedContent = decryptedContent
        self.signatureVerified = signatureVerified
    }

    /// Formatted date string for display
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    /// A preview of the ciphertext (first 32 chars of base64)
    var ciphertextPreview: String {
        let base64 = encryptedEnvelope.ciphertext.base64EncodedString()
        let prefix = String(base64.prefix(32))
        return "\(prefix)..."
    }
}

/// Represents a contact whose public key we have
struct Contact: Identifiable, Codable {
    let id: UUID
    var name: String
    let publicKeyData: Data
    let signingPublicKeyData: Data?
    let dateAdded: Date

    init(
        id: UUID = UUID(),
        name: String,
        publicKeyData: Data,
        signingPublicKeyData: Data? = nil,
        dateAdded: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.publicKeyData = publicKeyData
        self.signingPublicKeyData = signingPublicKeyData
        self.dateAdded = dateAdded
    }

    /// Formatted public key fingerprint for display (first 16 hex chars)
    var keyFingerprint: String {
        let hex = publicKeyData.prefix(8).map { String(format: "%02x", $0) }.joined()
        return hex
    }

    /// Whether this contact has a signing key (for signature verification)
    var hasSigningKey: Bool {
        signingPublicKeyData != nil
    }
}
