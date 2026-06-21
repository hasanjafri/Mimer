import XCTest
import CryptoKit
@testable import Mimer

@MainActor
final class SnippetTests: XCTestCase {
    private func makeStore() -> ClipStore {
        let store = ClipStore(
            persistence: PersistenceController(inMemory: true),
            cryptor: Cryptor(key: SymmetricKey(data: Data(repeating: 9, count: 32)))
        )
        store.loadInitial()
        return store
    }

    func testAddSnippetAppearsInSnippetsNotHistory() {
        let store = makeStore()
        store.addSnippet("my reusable snippet")
        XCTAssertEqual(store.snippets.map(\.text), ["my reusable snippet"])
        XCTAssertEqual(store.snippets.first?.kind, .snippet)
        XCTAssertTrue(store.items.isEmpty)
    }

    func testSnippetNotDedupedAgainstHistory() {
        let store = makeStore()
        store.insert(text: "shared text")
        store.addSnippet("shared text")
        XCTAssertEqual(store.items.map(\.text), ["shared text"])      // history keeps its copy
        XCTAssertEqual(store.snippets.map(\.text), ["shared text"])   // snippet is independent
    }

    func testSnippetsSurvivePruning() {
        let store = makeStore()
        store.historyLimitOverride = 2
        store.addSnippet("keep me forever")
        for i in 0..<5 { store.insert(text: "clip \(i)") }
        XCTAssertEqual(store.snippets.map(\.text), ["keep me forever"])  // never pruned
        XCTAssertLessThanOrEqual(store.items.count, 2)
    }

    func testDuplicateSnippetIgnored() {
        let store = makeStore()
        store.addSnippet("dup")
        store.addSnippet("dup")
        XCTAssertEqual(store.snippets.count, 1)
    }

    func testBlankSnippetIgnored() {
        let store = makeStore()
        store.addSnippet("   \n  ")
        XCTAssertTrue(store.snippets.isEmpty)
    }
}
