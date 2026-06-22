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

    /// hash is hex (HMAC) → a safe, traversal-free filename.
    private func url(for hash: String) -> URL { dir.appendingPathComponent(hash) }

    /// Store bytes, returning the content hash (the blob reference) or nil on failure.
    /// Idempotent: identical bytes map to the same file, so re-storing dedupes (no rewrite).
    func store(_ data: Data) -> String? {
        let hash = cryptor.dedupeHash(data)
        let fileURL = url(for: hash)
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

    /// Load + decrypt a blob, or nil if missing/corrupt.
    func load(_ hash: String) -> Data? {
        guard let sealed = try? Data(contentsOf: url(for: hash)) else { return nil }
        return cryptor.open(sealed)
    }

    func exists(_ hash: String) -> Bool { FileManager.default.fileExists(atPath: url(for: hash).path) }

    /// Remove a blob (called when its clip is pruned/deleted). Missing → no-op.
    func delete(_ hash: String) {
        try? FileManager.default.removeItem(at: url(for: hash))
    }
}
