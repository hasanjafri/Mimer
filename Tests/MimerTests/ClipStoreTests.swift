import XCTest
import Foundation
@testable import Mimer

@MainActor
final class ClipStoreTests: XCTestCase {
    private func makeStore(limit: Int? = nil, url: URL? = nil) -> ClipStore {
        let persistence = PersistenceController(inMemory: url == nil, storeURL: url)
        let store = ClipStore(persistence: persistence)
        store.historyLimitOverride = limit
        store.loadInitial()
        return store
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
}
