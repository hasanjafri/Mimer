import XCTest
import CryptoKit
@testable import Mimer

final class BlobStoreTests: XCTestCase {
    private func makeStore() -> (BlobStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("blobs-\(UUID().uuidString)", isDirectory: true)
        let cryptor = Cryptor(key: SymmetricKey(data: Data(repeating: 5, count: 32)))
        return (BlobStore(directory: dir, cryptor: cryptor), dir)
    }

    func testStoreLoadRoundTrip() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = Data((0..<512).map { UInt8($0 % 256) })
        guard let hash = store.store(data) else { return XCTFail("store failed") }
        XCTAssertTrue(store.exists(hash))
        XCTAssertEqual(store.load(hash), data)
    }

    func testEncryptedOnDisk() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = Data("the secret image bytes ZZZ".utf8)
        let hash = store.store(data)!
        let onDisk = try! Data(contentsOf: dir.appendingPathComponent(hash))
        XCTAssertNotEqual(onDisk, data)                       // ciphertext, not raw
        XCTAssertFalse(onDisk.range(of: data) != nil)         // plaintext bytes absent
    }

    func testDedupeSameBytesOneFile() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let data = Data("dup".utf8) + Data(repeating: 7, count: 100)
        let h1 = store.store(data)
        let h2 = store.store(data)
        XCTAssertEqual(h1, h2)
        let files = try! FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(files.count, 1)                        // stored once
    }

    func testLoadMissingAndDelete() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertNil(store.load("deadbeef"))                  // missing → nil, no crash
        let hash = store.store(Data(repeating: 1, count: 64))!
        store.delete(hash)
        XCTAssertFalse(store.exists(hash))
        store.delete(hash)                                   // double delete → no-op
    }

    func testWrongKeyCannotDecrypt() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let hash = store.store(Data(repeating: 9, count: 64))!
        let other = BlobStore(directory: dir, cryptor: Cryptor(key: SymmetricKey(data: Data(repeating: 6, count: 32))))
        XCTAssertNil(other.load(hash))                        // different key → can't open
    }
}
