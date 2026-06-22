import Foundation

/// Encrypted, content-addressed store for binary clip payloads (images). Each blob is named by
/// its **keyed** content hash (so identical bytes dedupe to one file and the filename leaks
/// nothing) and written **AES-GCM-encrypted** via `Cryptor` — so the blob directory is
/// ciphertext-only, exactly like the sqlite. Lives under Application Support/Mimer/blobs/.
/// Sendable value type (URL + Sendable Cryptor) so it's safe to use from any isolation.
struct BlobStore: Sendable {
    private let dir: URL
    private let cryptor: Cryptor

    init(directory: URL? = nil, cryptor: Cryptor = .shared) {
        self.cryptor = cryptor
        dir = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mimer/blobs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    /// The content key (== filename) these bytes will get. The single source of truth for the
    /// blob hash, so callers persist exactly what `store` writes (no independent recomputation).
    func hash(for data: Data) -> String { cryptor.dedupeHash(data) }

    /// A blob URL only for a well-formed hash (64 lowercase hex = HMAC-SHA256). Anything else
    /// (DB/sync tampering) → nil, so a stored value can never become a path-traversal filename.
    private func url(for hash: String) -> URL? {
        guard hash.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else { return nil }
        return dir.appendingPathComponent(hash)
    }

    /// Store bytes, returning the content hash (the blob reference) or nil on failure.
    /// Idempotent: identical bytes map to the same file, so re-storing dedupes (no rewrite).
    func store(_ data: Data) -> String? {
        let hash = cryptor.dedupeHash(data)
        guard let fileURL = url(for: hash) else { return nil }
        if FileManager.default.fileExists(atPath: fileURL.path) { return hash }   // dedupe
        guard let sealed = cryptor.seal(data) else {                              // fail closed
            NSLog("Mimer BlobStore: seal failed; not writing blob")
            return nil
        }
        do {
            try sealed.write(to: fileURL, options: .atomic)
            return hash
        } catch {
            NSLog("Mimer BlobStore: write failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Load + decrypt a blob, or nil if missing/corrupt/malformed-hash.
    func load(_ hash: String) -> Data? {
        guard let fileURL = url(for: hash), let sealed = try? Data(contentsOf: fileURL) else { return nil }
        return cryptor.open(sealed)
    }

    func exists(_ hash: String) -> Bool {
        guard let fileURL = url(for: hash) else { return false }
        return FileManager.default.fileExists(atPath: fileURL.path)
    }

    /// Remove a blob (called when its clip is pruned/deleted). Missing/malformed → no-op.
    func delete(_ hash: String) {
        guard let fileURL = url(for: hash) else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
