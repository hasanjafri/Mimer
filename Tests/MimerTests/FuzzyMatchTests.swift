import XCTest
@testable import Mimer

final class FuzzyMatchTests: XCTestCase {
    func testSubsequenceMatches() {
        XCTAssertTrue(fuzzyMatch("fpst", "func paste()"))     // gaps allowed
        XCTAssertTrue(fuzzyMatch("hw", "Hello, world"))
        XCTAssertTrue(fuzzyMatch("url", "https://example.com/URL"))  // case-insensitive
        XCTAssertTrue(fuzzyMatch("", "anything"))             // empty → match all
        XCTAssertTrue(fuzzyMatch("paste", "paste"))           // exact
    }

    func testNonMatches() {
        XCTAssertFalse(fuzzyMatch("xyz", "func paste"))
        XCTAssertFalse(fuzzyMatch("paf", "func paste"))       // out of order
        XCTAssertFalse(fuzzyMatch("pastes", "paste"))         // needle longer
    }
}
