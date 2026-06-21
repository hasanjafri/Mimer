import XCTest
import Foundation
@testable import Mimer

final class PasteStackTests: XCTestCase {
    private func item(_ text: String) -> ClipItem {
        ClipItem(id: UUID(), text: text, kind: .text, createdAt: Date(), isFavorite: false)
    }

    func testToggleAddsAndRemovesPreservingOrder() {
        let a = item("a"), b = item("b"), c = item("c")
        var s = PasteStack()
        s.toggle(a.id); s.toggle(b.id); s.toggle(c.id)
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.position(of: a.id), 1)
        XCTAssertEqual(s.position(of: c.id), 3)

        s.toggle(b.id)                       // remove the middle
        XCTAssertNil(s.position(of: b.id))
        XCTAssertEqual(s.position(of: a.id), 1)
        XCTAssertEqual(s.position(of: c.id), 2)   // c renumbers to 2
    }

    func testOrderedResolvesInStackOrderAndDropsMissing() {
        let a = item("alpha"), b = item("beta"), c = item("gamma")
        var s = PasteStack()
        s.toggle(c.id); s.toggle(a.id)       // stack order: c, a
        let ordered = s.ordered(from: [a, b, c])   // candidates in a different order
        XCTAssertEqual(ordered.map(\.text), ["gamma", "alpha"])

        // A stacked id that no longer resolves (deleted clip) is dropped, not crashed.
        let ghost = s.ordered(from: [b])
        XCTAssertTrue(ghost.isEmpty)
    }

    func testRemoveKeepsCountAccurate() {
        let a = item("a"), b = item("b"), c = item("c")
        var s = PasteStack()
        s.toggle(a.id); s.toggle(b.id); s.toggle(c.id)
        s.remove(b.id)                       // e.g. b's clip was deleted
        XCTAssertEqual(s.count, 2)
        XCTAssertNil(s.position(of: b.id))
        XCTAssertEqual(s.position(of: c.id), 2)
        s.remove(b.id)                       // removing a non-member is a no-op
        XCTAssertEqual(s.count, 2)
    }

    func testClearAndEmpty() {
        let a = item("a")
        var s = PasteStack()
        XCTAssertTrue(s.isEmpty)
        s.toggle(a.id)
        XCTAssertFalse(s.isEmpty)
        s.clear()
        XCTAssertTrue(s.isEmpty)
    }
}
