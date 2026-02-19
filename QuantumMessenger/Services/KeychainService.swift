import Foundation
import Security
import CryptoKit

// MARK: - KeychainError

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case unexpectedDataFormat

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            let msg = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Keychain save failed: \(msg)"
        case .loadFailed(let status):
            let msg = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Keychain load failed: \(msg)"
        case .deleteFailed(let status):
            let msg = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Keychain delete failed: \(msg)"
        case .unexpectedDataFormat:
            return "Keychain returned data in an unexpected format"
        }
    }
}

// MARK: - KeychainService

/// Manages secure storage of cryptographic keys using the iOS Keychain.
///
/// Storage tiers:
///   - Private keys  → Keychain, kSecAttrAccessibleWhenUnlockedThisDeviceOnly
///                     (locked when screen locks, never leaves device, never backed up)
///   - Public keys   → Keychain, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
///                     (available to background tasks after first unlock, stays on device)
///   - Contacts      → UserDefaults  (public-key material only, not secret)
///   - Messages      → UserDefaults  (ciphertext envelopes; decryptedContent is cleared
///                     before persisting so plaintext never hits disk)
@available(iOS 26.0, macOS 26.0, *)
final class KeychainService {

    // MARK: - Service / Account labels

    private static let service = "com.quantummessenger.keychain"

    private enum Account: String {
        case encryptionPrivateKey  = "xwing.private"
        case encryptionPublicKey   = "xwing.public"
        case signingPrivateKey     = "mldsa65.private"
        case signingPublicKey      = "mldsa65.public"
    }

    private static let contactsDefaultsKey = "com.quantummessenger.contacts"
    private static let messagesDefaultsKey  = "com.quantummessenger.messages"

    // MARK: - Encryption Key Pair

    /// Save the X-Wing key pair to the Keychain.
    /// Private key is stored with `WhenUnlockedThisDeviceOnly` — it is never accessible
    /// while the screen is locked and never leaves this device.
    static func saveKeyPair(
        privateKey: XWingMLKEM768X25519.PrivateKey,
        publicKey: XWingMLKEM768X25519.PublicKey
    ) throws {
        let privateData = try CryptoService.exportPrivateKey(privateKey)
        let publicData  = CryptoService.exportPublicKey(publicKey)

        try keychainSave(
            account: Account.encryptionPrivateKey.rawValue,
            data: privateData,
            accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        )
        try keychainSave(
            account: Account.encryptionPublicKey.rawValue,
            data: publicData,
            accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        )
    }

    /// Load the X-Wing private key from the Keychain.
    static func loadPrivateKey() -> XWingMLKEM768X25519.PrivateKey? {
        guard let data = keychainLoad(account: Account.encryptionPrivateKey.rawValue) else {
            return nil
        }
        return try? CryptoService.importPrivateKey(from: data)
    }

    /// Load the X-Wing public key from the Keychain.
    static func loadPublicKey() -> XWingMLKEM768X25519.PublicKey? {
        guard let data = keychainLoad(account: Account.encryptionPublicKey.rawValue) else {
            return nil
        }
        return try? CryptoService.importPublicKey(from: data)
    }

    /// Returns true if an encryption key pair exists in the Keychain.
    static func hasKeyPair() -> Bool {
        keychainLoad(account: Account.encryptionPrivateKey.rawValue) != nil
    }

    /// Delete the X-Wing key pair from the Keychain.
    static func deleteKeyPair() {
        keychainDelete(account: Account.encryptionPrivateKey.rawValue)
        keychainDelete(account: Account.encryptionPublicKey.rawValue)
    }

    // MARK: - Signing Key Pair

    /// Save the ML-DSA-65 signing key pair to the Keychain.
    static func saveSigningKeyPair(
        privateKey: MLDSA65.PrivateKey,
        publicKey: MLDSA65.PublicKey
    ) throws {
        let privateData = try CryptoService.exportSigningPrivateKey(privateKey)
        let publicData  = CryptoService.exportSigningPublicKey(publicKey)

        try keychainSave(
            account: Account.signingPrivateKey.rawValue,
            data: privateData,
            accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        )
        try keychainSave(
            account: Account.signingPublicKey.rawValue,
            data: publicData,
            accessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        )
    }

    /// Load the ML-DSA-65 signing private key from the Keychain.
    static func loadSigningPrivateKey() -> MLDSA65.PrivateKey? {
        guard let data = keychainLoad(account: Account.signingPrivateKey.rawValue) else {
            return nil
        }
        return try? CryptoService.importSigningPrivateKey(from: data)
    }

    /// Load the ML-DSA-65 signing public key from the Keychain.
    static func loadSigningPublicKey() -> MLDSA65.PublicKey? {
        guard let data = keychainLoad(account: Account.signingPublicKey.rawValue) else {
            return nil
        }
        return try? CryptoService.importSigningPublicKey(from: data)
    }

    /// Returns true if a signing key pair exists in the Keychain.
    static func hasSigningKeyPair() -> Bool {
        keychainLoad(account: Account.signingPrivateKey.rawValue) != nil
    }

    /// Delete the ML-DSA-65 signing key pair from the Keychain.
    static func deleteSigningKeyPair() {
        keychainDelete(account: Account.signingPrivateKey.rawValue)
        keychainDelete(account: Account.signingPublicKey.rawValue)
    }

    // MARK: - Contact Storage (UserDefaults — public-key material only)

    static func saveContacts(_ contacts: [Contact]) {
        if let data = try? JSONEncoder().encode(contacts) {
            UserDefaults.standard.set(data, forKey: contactsDefaultsKey)
        }
    }

    static func loadContacts() -> [Contact] {
        guard let data = UserDefaults.standard.data(forKey: contactsDefaultsKey),
              let contacts = try? JSONDecoder().decode([Contact].self, from: data) else {
            return []
        }
        return contacts
    }

    // MARK: - Message Storage (UserDefaults — encrypted envelopes only)
    //
    // decryptedContent is intentionally stripped before saving so plaintext
    // never touches disk. The user re-decrypts after each app launch.

    static func saveMessages(_ messages: [EncryptedMessage]) {
        let stripped = messages.map { $0.withoutDecryptedContent() }
        if let data = try? JSONEncoder().encode(stripped) {
            UserDefaults.standard.set(data, forKey: messagesDefaultsKey)
        }
    }

    static func loadMessages() -> [EncryptedMessage] {
        guard let data = UserDefaults.standard.data(forKey: messagesDefaultsKey),
              let messages = try? JSONDecoder().decode([EncryptedMessage].self, from: data) else {
            return []
        }
        return messages
    }

    // MARK: - Migrate from UserDefaults (one-time upgrade path)
    //
    // On first launch after upgrading from the UserDefaults-based version,
    // any existing keys are migrated into the Keychain and removed from UserDefaults.

    static func migrateFromUserDefaultsIfNeeded() {
        let legacyPrivKey   = "com.quantummessenger.privateKey"
        let legacyPubKey    = "com.quantummessenger.publicKey"
        let legacySigPriv   = "com.quantummessenger.signingPrivateKey"
        let legacySigPub    = "com.quantummessenger.signingPublicKey"

        let ud = UserDefaults.standard

        // Migrate encryption key pair
        if let privData = ud.data(forKey: legacyPrivKey),
           let pubData  = ud.data(forKey: legacyPubKey),
           !hasKeyPair() {
            if let privKey = try? CryptoService.importPrivateKey(from: privData),
               let pubKey  = try? CryptoService.importPublicKey(from: pubData) {
                try? saveKeyPair(privateKey: privKey, publicKey: pubKey)
            }
            ud.removeObject(forKey: legacyPrivKey)
            ud.removeObject(forKey: legacyPubKey)
        }

        // Migrate signing key pair
        if let sigPrivData = ud.data(forKey: legacySigPriv),
           let sigPubData  = ud.data(forKey: legacySigPub),
           !hasSigningKeyPair() {
            if let sigPrivKey = try? CryptoService.importSigningPrivateKey(from: sigPrivData),
               let sigPubKey  = try? CryptoService.importSigningPublicKey(from: sigPubData) {
                try? saveSigningKeyPair(privateKey: sigPrivKey, publicKey: sigPubKey)
            }
            ud.removeObject(forKey: legacySigPriv)
            ud.removeObject(forKey: legacySigPub)
        }
    }

    // MARK: - Private Keychain Helpers

    /// Upsert (add or update) a generic password item in the Keychain.
    private static func keychainSave(
        account: String,
        data: Data,
        accessible: CFString
    ) throws {
        let query: [CFString: Any] = [
            kSecClass:        kSecClassGenericPassword,
            kSecAttrService:  service,
            kSecAttrAccount:  account
        ]

        // Attempt update first — if the item already exists this avoids duplicates.
        let updateAttributes: [CFString: Any] = [
            kSecValueData:     data,
            kSecAttrAccessible: accessible
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)

        switch updateStatus {
        case errSecSuccess:
            return  // Updated in place — done.

        case errSecItemNotFound:
            // Item doesn't exist yet — add it.
            var addQuery = query
            addQuery[kSecValueData]      = data
            addQuery[kSecAttrAccessible] = accessible
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.saveFailed(addStatus)
            }

        default:
            throw KeychainError.saveFailed(updateStatus)
        }
    }

    /// Load the raw data for a generic password item from the Keychain.
    /// Returns nil if the item doesn't exist (not an error condition).
    private static func keychainLoad(account: String) -> Data? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return data
    }

    /// Delete a generic password item from the Keychain.
    /// Silently ignores errSecItemNotFound (idempotent).
    private static func keychainDelete(account: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        // errSecItemNotFound is fine — item was already absent.
        assert(
            status == errSecSuccess || status == errSecItemNotFound,
            "Unexpected Keychain delete status: \(status)"
        )
    }
}
