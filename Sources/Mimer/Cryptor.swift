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

    // Domain-separated subkeys derived from the master via HKDF — the AES key and the
    // dedupe-HMAC key are never the same bytes used for two purposes.
    private let aesKey: SymmetricKey
    private let macKey: SymmetricKey

    /// False when the master key is an ephemeral fallback (Keychain unusable) — the key won't
    /// survive a restart, so the store must run non-destructively (skip the legacy-plaintext
    /// migration + vacuum) to avoid scrubbing still-recoverable data. True for tests + the
    /// normal Keychain-backed key.
    let isDurable: Bool

    init(key master: SymmetricKey, durable: Bool = true) {
        aesKey = Self.derive(master, info: "Mimer/aes-gcm/v1")
        macKey = Self.derive(master, info: "Mimer/dedupe-hmac/v1")
        isDurable = durable
    }

    private static func derive(_ master: SymmetricKey, info: String) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(inputKeyMaterial: master, info: Data(info.utf8), outputByteCount: 32)
    }

    /// The app-wide instance, keyed from the macOS Keychain (created on first run).
    static let shared: Cryptor = {
        let k = KeychainKey.loadOrCreate()
        return Cryptor(key: k.key, durable: k.durable)
    }()

    func isEncrypted(_ stored: String) -> Bool { stored.hasPrefix(Self.prefix) }

    /// `"enc:v1:" + base64(nonce|ciphertext|tag)`, or **nil on failure**. Callers must
    /// fail closed — never fall back to writing plaintext (that would defeat the feature).
    func encrypt(_ plaintext: String) -> String? {
        guard let sealed = try? AES.GCM.seal(Data(plaintext.utf8), using: aesKey),
              let combined = sealed.combined else {
            NSLog("Mimer Cryptor: seal failed; refusing to store this clip")
            return nil
        }
        return Self.prefix + combined.base64EncodedString()
    }

    /// Returns plaintext. Un-prefixed (legacy) input is returned unchanged; an
    /// encrypted value that can't be opened (corrupt, or a different key — e.g. the
    /// Keychain key was lost) returns nil so the caller can flag the unreadable row.
    func decrypt(_ stored: String) -> String? {
        guard stored.hasPrefix(Self.prefix) else { return stored }
        let b64 = String(stored.dropFirst(Self.prefix.count))
        guard let data = Data(base64Encoded: b64),
              let box = try? AES.GCM.SealedBox(combined: data),
              let opened = try? AES.GCM.open(box, using: aesKey) else { return nil }
        return String(decoding: opened, as: UTF8.self)
    }

    /// Deterministic dedupe fingerprint (HMAC-SHA256 hex) of the plaintext. Keyed,
    /// so the stored hash can't be used to confirm a guessed clip without the key.
    func dedupeHash(_ plaintext: String) -> String {
        dedupeHash(Data(plaintext.utf8))
    }

    /// HMAC-SHA256 hex of raw bytes — used to content-address (and dedupe) image blobs.
    func dedupeHash(_ data: Data) -> String {
        HMAC<SHA256>.authenticationCode(for: data, using: macKey).map { String(format: "%02x", $0) }.joined()
    }

    /// Encrypt raw bytes (image blobs): AES-GCM `nonce|ciphertext|tag`, or nil on failure.
    func seal(_ data: Data) -> Data? {
        (try? AES.GCM.seal(data, using: aesKey))?.combined
    }

    /// Decrypt bytes produced by `seal`, or nil if corrupt / wrong key.
    func open(_ data: Data) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(box, using: aesKey)
    }
}

/// The 256-bit history master key, stored in the macOS Keychain (this-device-only,
/// never iCloud-synced), generated on first run. Hardened against the realistic
/// failure (an item already exists → reuse it). Only if the Keychain is genuinely
/// unusable do we fall back to an ephemeral key — logged loudly, because history
/// then won't survive a restart. Tests never reach this path: they inject a `Cryptor`
/// with an explicit key.
enum KeychainKey {
    private static let service = "com.hasanjafri.Mimer"
    private static let account = "history-encryption-key-v1"

    /// Returns the master key and whether it is *durable* (persisted in the Keychain).
    /// `durable == false` means an ephemeral fallback — the caller must degrade to a
    /// non-destructive, in-memory-only session.
    static func loadOrCreate() -> (key: SymmetricKey, durable: Bool) {
        if let data = load(), data.count == 32 { return (SymmetricKey(data: data), true) }

        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data(Array($0)) }
        let status = add(data)
        switch status {
        case errSecSuccess:
            return (key, true)
        case errSecDuplicateItem:
            // Raced with another launch, or a stale/invalid item exists.
            if let existing = load(), existing.count == 32 { return (SymmetricKey(data: existing), true) }
            if update(data) { return (key, true) }
            return (ephemeral("could not replace an unusable Keychain item"), false)
        default:
            return (ephemeral("Keychain add failed (OSStatus \(status))"), false)
        }
    }

    private static func ephemeral(_ why: String) -> SymmetricKey {
        NSLog("Mimer: CRITICAL — \(why); using an ephemeral key. New clips won't survive a restart, and existing encrypted history is left untouched (not migrated/scrubbed) until the Keychain recovers.")
        return SymmetricKey(size: .bits256)
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

    private static func add(_ data: Data) -> OSStatus {
        var q = baseQuery()
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(q as CFDictionary, nil)
    }

    private static func update(_ data: Data) -> Bool {
        let attrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        return SecItemUpdate(baseQuery() as CFDictionary, attrs as CFDictionary) == errSecSuccess
    }
}
