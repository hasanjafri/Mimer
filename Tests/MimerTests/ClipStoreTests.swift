import XCTest
import Foundation
import CryptoKit
import CoreData
@testable import Mimer

@MainActor
final class ClipStoreTests: XCTestCase {
    // Fixed key (never the Keychain) so tests are deterministic and a reopened store
    // on the same file can still decrypt what the first one wrote.
    private let cryptor = Cryptor(key: SymmetricKey(data: Data(repeating: 7, count: 32)))
    // A temp blob dir per test class instance so image-clip tests never touch the real store.
    private lazy var blobDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("clipstore-blobs-\(UUID().uuidString)", isDirectory: true)

    override func tearDown() {
        try? FileManager.default.removeItem(at: blobDir)
        super.tearDown()
    }

    private func makeStore(limit: Int? = nil, url: URL? = nil) -> ClipStore {
        let persistence = PersistenceController(inMemory: url == nil, storeURL: url)
        let blobStore = BlobStore(directory: blobDir, cryptor: cryptor)
        let store = ClipStore(persistence: persistence, cryptor: cryptor, blobStore: blobStore)
        store.historyLimitOverride = limit
        store.loadInitial()
        return store
    }

    func testCapturesSourceApp() {
        let store = makeStore()
        store.insert(text: "from terminal", sourceApp: "Terminal")
        store.insert(text: "no source")
        XCTAssertEqual(store.items.first(where: { $0.text == "from terminal" })?.sourceApp, "Terminal")
        XCTAssertNil(store.items.first(where: { $0.text == "no source" })?.sourceApp)
    }

    func testReCaptureRefreshesSourceApp() {
        let store = makeStore()
        store.insert(text: "shared", sourceApp: "Safari")
        store.insert(text: "shared", sourceApp: "Terminal")   // dedupe → same row, newest source wins
        XCTAssertEqual(store.items.filter { $0.text == "shared" }.count, 1)
        XCTAssertEqual(store.items.first(where: { $0.text == "shared" })?.sourceApp, "Terminal")
    }

    func testInsertImageStoresBlobAndRow() {
        let store = makeStore()
        let img = Data("fake-png-bytes".utf8) + Data(repeating: 42, count: 200)
        store.insertImage(data: img)
        let item = store.items.first
        XCTAssertEqual(item?.kind, .image)
        XCTAssertNotNil(item?.blobHash)
        XCTAssertEqual(store.blobData(item!.blobHash!), img)   // round-trips through the encrypted blob
    }

    func testInsertImageDedupes() {
        let store = makeStore()
        let img = Data(repeating: 7, count: 300)
        store.insertImage(data: img)
        store.insert(text: "between")
        store.insertImage(data: img)                           // same bytes → dedupe, move to top
        XCTAssertEqual(store.items.filter { $0.kind == .image }.count, 1)
        XCTAssertEqual(store.items.first?.kind, .image)        // moved to top
    }

    func testDeleteImageRemovesBlob() {
        let store = makeStore()
        store.insertImage(data: Data(repeating: 3, count: 128))
        let item = store.items.first { $0.kind == .image }!
        let hash = item.blobHash!
        XCTAssertNotNil(store.blobData(hash))
        store.delete(item.id)
        XCTAssertNil(store.blobData(hash))                     // blob file removed with the row
    }

    func testPruneRemovesOverflowImageBlobs() {
        let store = makeStore(limit: 2)
        let imgs = (0..<3).map { Data("img\($0)".utf8) + Data(repeating: UInt8($0), count: 64) }
        let hashes = imgs.map { Cryptor(key: SymmetricKey(data: Data(repeating: 7, count: 32))).dedupeHash($0) }
        for img in imgs { store.insertImage(data: img) }       // 3 images, cap 2 → oldest pruned
        XCTAssertLessThanOrEqual(store.items.count, 2)
        XCTAssertNil(store.blobData(hashes[0]))                // oldest image's blob is gone
        XCTAssertNotNil(store.blobData(hashes[2]))             // newest survives
    }

    func testInsertOrdersNewestFirst() {
        let store = makeStore()
        store.insert(text: "alpha")
        store.insert(text: "beta")
        XCTAssertEqual(store.items.map(\.text), ["beta", "alpha"])
    }

    func testDedupeMovesToTop() {
        let store = makeStore()
        store.insert(text: "alpha")
        store.insert(text: "beta")
        store.insert(text: "alpha")
        XCTAssertEqual(store.items.map(\.text), ["alpha", "beta"])
        XCTAssertEqual(store.items.count, 2)
    }

    func testPrunesToHistoryLimitButKeepsFavorites() {
        let store = makeStore(limit: 3)
        for s in ["a", "b", "c", "d", "e"] { store.insert(text: s) }
        XCTAssertEqual(store.items.map(\.text), ["e", "d", "c"])

        // Favorite a survivor, then overflow again — the favorite stays.
        if let c = store.items.first(where: { $0.text == "c" }) {
            store.setFavorite(c.id, true)
        }
        for s in ["f", "g", "h"] { store.insert(text: s) }
        XCTAssertTrue(store.items.contains { $0.text == "c" }, "favorite must not be pruned")
    }

    func testFavoritePinsToTopAndToggles() {
        let store = makeStore()
        store.insert(text: "a")
        store.insert(text: "b")
        store.insert(text: "c")   // newest-first: c, b, a

        let a = store.items.first { $0.text == "a" }!
        store.toggleFavorite(a.id)
        XCTAssertEqual(store.items.first?.text, "a")          // favorite pinned to top
        XCTAssertEqual(store.items.first?.isFavorite, true)

        store.toggleFavorite(a.id)                            // unfavorite → back to chronological
        XCTAssertEqual(store.items.map(\.text), ["c", "b", "a"])
    }

    func testPersistsAcrossReopen() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MimerStoreTest-\(UUID().uuidString).sqlite")
        defer {
            for ext in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + ext))
            }
        }
        let first = makeStore(url: url)
        first.insert(text: "remember me")

        let second = makeStore(url: url)   // fresh store, same file
        XCTAssertTrue(second.items.contains { $0.text == "remember me" })
    }

    func testStoresCiphertextNotPlaintextOnDisk() {
        let persistence = PersistenceController(inMemory: true)
        let store = ClipStore(persistence: persistence, cryptor: cryptor)
        store.loadInitial()
        store.insert(text: "top secret value")

        XCTAssertEqual(store.items.first?.text, "top secret value")   // decrypts in memory

        // The raw column must be ciphertext — plaintext never hits the store.
        let raw = (try? persistence.viewContext.fetch(Clip.fetch()))?.first?.text
        XCTAssertNotNil(raw)
        XCTAssertTrue(raw!.hasPrefix(Cryptor.prefix))
        XCTAssertFalse(raw!.contains("top secret value"))
    }

    func testMigratesLegacyPlaintextRowsOnLoad() {
        let persistence = PersistenceController(inMemory: true)
        let ctx = persistence.viewContext
        // Simulate a pre-encryption row: plaintext text + old SHA-256-style hash.
        let clip = NSEntityDescription.insertNewObject(forEntityName: "Clip", into: ctx) as! Clip
        clip.id = UUID()
        clip.text = "legacy plaintext"
        clip.contentHash = "old-sha256-hash"
        clip.kind = 0
        clip.createdAt = Date()
        clip.lastUsedAt = Date()
        clip.isFavorite = false
        try? ctx.save()

        let store = ClipStore(persistence: persistence, cryptor: cryptor)
        store.loadInitial()   // runs the migration

        XCTAssertEqual(store.items.map(\.text), ["legacy plaintext"])   // still readable

        let migrated = (try? ctx.fetch(Clip.fetch()))?.first
        XCTAssertTrue(migrated?.text?.hasPrefix(Cryptor.prefix) ?? false, "row is now encrypted")
        XCTAssertEqual(migrated?.contentHash, cryptor.dedupeHash("legacy plaintext"), "hash recomputed as HMAC")
    }

    // The security-critical case: an ephemeral session must NOT migrate legacy plaintext into
    // ciphertext it can't read back — that would scrub recoverable data. The row stays plaintext.
    func testEphemeralKeyDoesNotMigrateLegacyPlaintext() {
        let persistence = PersistenceController(inMemory: true)
        let ctx = persistence.viewContext
        let clip = NSEntityDescription.insertNewObject(forEntityName: "Clip", into: ctx) as! Clip
        clip.id = UUID(); clip.text = "recoverable legacy plaintext"; clip.contentHash = "old"
        clip.kind = 0; clip.createdAt = Date(); clip.lastUsedAt = Date(); clip.isFavorite = false
        try? ctx.save()

        let ephemeral = Cryptor(key: SymmetricKey(data: Data(repeating: 9, count: 32)), durable: false)
        let store = ClipStore(persistence: persistence, cryptor: ephemeral)
        store.loadInitial()   // migration must be SKIPPED with a non-durable key

        let raw = (try? ctx.fetch(Clip.fetch()))?.first?.text
        XCTAssertEqual(raw, "recoverable legacy plaintext", "ephemeral session must not scrub recoverable plaintext")
    }

    func testMigrationVacuumsFileStoreWithoutDataLoss() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MimerVacuumTest-\(UUID().uuidString).sqlite")
        defer {
            for ext in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + ext))
            }
        }
        // Seed legacy plaintext directly into a file-backed store, then close it.
        do {
            let persistence = PersistenceController(inMemory: false, storeURL: url)
            let ctx = persistence.viewContext
            let clip = NSEntityDescription.insertNewObject(forEntityName: "Clip", into: ctx) as! Clip
            clip.id = UUID(); clip.text = "vacuum me"; clip.contentHash = "old"
            clip.kind = 0; clip.createdAt = Date(); clip.lastUsedAt = Date(); clip.isFavorite = false
            try? ctx.save()
        }
        // Reopen: migration rewrites the row and vacuum() runs (remove/re-add store).
        let store = makeStore(url: url)
        XCTAssertEqual(store.items.map(\.text), ["vacuum me"], "data survives the vacuum/store-reset")
    }
}
