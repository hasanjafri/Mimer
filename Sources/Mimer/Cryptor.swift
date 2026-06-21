import Foundation
import CryptoKit
import Security

/// App-layer encryption for clip text stored on disk. Mimer's Core Data model is
/// kept CloudKit-valid (a future `NSPersistentCloudKitContainer` swap), which rules
/// out SQLCipher (whole-DB encryption is incompatible with CloudKit). So we encrypt
/// the sensitive *field* instead: `text` is stored as `"enc:v1:" + base64(AES-GCM)`,
/// and the dedupe fingerprint is an HMAC of the plaintext (the stored hash reveals
/// nothing without the key, and ciphertext syncs to CloudKit just fine).
///
/// Decryption is in-memory only (`ClipItem.text`); search and sort run on those
/// decrypted values, never on the DB column, so encryption doesn't touch the query
/// path. Legacy (un-prefixed) values are treated as plaintext and migrated lazily.
struct Cryptor {
    /// Versioned marker so we can detect encrypted values and evolve the scheme later.
    static let prefix = "enc:v1:"

    private let key: SymmetricKey

    init(key: SymmetricKey) { self.key = key }

    /// The app-wide instance, keyed from the macOS Keychain (created on first run).
    static let shared = Cryptor(key: KeychainKey.loadOrCreate())

    func isEncrypted(_ stored: String) -> Bool { stored.hasPrefix(Self.prefix) }

    /// `"enc:v1:" + base64(nonce|ciphertext|tag)`. On the (practically unreachable)
    /// seal failure we return plaintext rather than lose the clip — `decrypt` then
    /// round-trips it as a legacy value.
    func encrypt(_ plaintext: String) -> String {
        guard let sealed = try? AES.GCM.seal(Data(plaintext.utf8), using: key),
              let combined = sealed.combined else {
            NSLog("Mimer Cryptor: seal failed; storing plaintext for this clip")
            return plaintext
        }
        return Self.prefix + combined.base64EncodedString()
    }

    /// Returns plaintext. Un-prefixed (legacy) input is returned unchanged; an
    /// encrypted value that can't be opened (corrupt, or a different key — e.g. the
    /// Keychain key was lost) returns nil so the caller can skip the unreadable row.
    func decrypt(_ stored: String) -> String? {
        guard stored.hasPrefix(Self.prefix) else { return stored }
        let b64 = String(stored.dropFirst(Self.prefix.count))
        guard let data = Data(base64Encoded: b64),
              let box = try? AES.GCM.SealedBox(combined: data),
              let opened = try? AES.GCM.open(box, using: key) else { return nil }
        return String(decoding: opened, as: UTF8.self)
    }

    /// Deterministic dedupe fingerprint (HMAC-SHA256 hex) of the plaintext. Keyed,
    /// so the stored hash can't be used to confirm a guessed clip without the key.
    func dedupeHash(_ plaintext: String) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: Data(plaintext.utf8), using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}

/// The 256-bit history key, stored in the macOS Keychain (this-device-only, never
/// iCloud-synced). Generated on first run. If the Keychain is unavailable (e.g. an
/// unsigned test runner) we fall back to an ephemeral process key so the app still
/// works — it just won't persist across launches.
enum KeychainKey {
    private static let service = "com.hasanjafri.Mimer"
    private static let account = "history-encryption-key-v1"

    static func loadOrCreate() -> SymmetricKey {
        if let data = load() { return SymmetricKey(data: data) }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data(Array($0)) }
        if !store(data) {
            NSLog("Mimer: could not persist encryption key to Keychain; using an ephemeral key")
        }
        return key
    }

    private static func baseQuery() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func load() -> Data? {
        var q = baseQuery()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    private static func store(_ data: Data) -> Bool {
        var q = baseQuery()
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }
}
