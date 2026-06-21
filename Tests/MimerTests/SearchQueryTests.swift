import XCTest
import Foundation
@testable import Mimer

final class SearchQueryTests: XCTestCase {
    private func item(_ text: String, kind: ClipKind = .text, fav: Bool = false) -> ClipItem {
        ClipItem(id: UUID(), text: text, kind: kind, createdAt: Date(), isFavorite: fav)
    }

    func testEmptyMatchesAll() {
        let q = SearchQuery.parse("")
        XCTAssertTrue(q.isEmpty)
        XCTAssertTrue(q.matches(item("anything")))
    }

    func testTypeFilter() {
        let q = SearchQuery.parse("type:link")
        XCTAssertEqual(q.kinds, [.link])
        XCTAssertTrue(q.matches(item("https://x.com", kind: .link)))
        XCTAssertFalse(q.matches(item("plain", kind: .text)))
    }

    func testTypeFileMatchesFileAndFileRef() {
        let q = SearchQuery.parse("type:file")
        XCTAssertTrue(q.matches(item("/a/b", kind: .fileRef)))
        XCTAssertTrue(q.matches(item("x", kind: .file)))
        XCTAssertFalse(q.matches(item("x", kind: .text)))
    }

    func testSecretFilterUsesLiveDetection() {
        let q = SearchQuery.parse("type:secret")
        XCTAssertTrue(q.onlySecrets)
        XCTAssertTrue(q.matches(item("AKIA" + "0123456789ABCDEF")))   // detected secret
        XCTAssertFalse(q.matches(item("not a secret")))
    }

    func testFavoriteFilter() {
        let q = SearchQuery.parse("is:fav")
        XCTAssertTrue(q.matches(item("x", fav: true)))
        XCTAssertFalse(q.matches(item("x", fav: false)))
    }

    func testTypePlusFuzzyText() {
        let q = SearchQuery.parse("type:link react")
        XCTAssertEqual(q.kinds, [.link])
        XCTAssertEqual(q.text, "react")
        XCTAssertTrue(q.matches(item("https://react.dev", kind: .link)))
        XCTAssertFalse(q.matches(item("https://vue.dev", kind: .link)))   // fuzzy "react" fails
    }

    func testRegexMode() {
        let q = SearchQuery.parse("/git.*hub/")
        XCTAssertNotNil(q.regex)
        XCTAssertTrue(q.matches(item("see github.com/x")))
        XCTAssertFalse(q.matches(item("see gitlab.com/x")))
    }

    func testInvalidRegexFallsBackToFuzzy() {
        let q = SearchQuery.parse("/[unclosed/")
        XCTAssertNil(q.regex)
        XCTAssertEqual(q.text, "/[unclosed/")          // treated literally
        XCTAssertTrue(q.matches(item("an /[unclosed/ token")))
    }

    func testUnknownTypeIsLiteralText() {
        let q = SearchQuery.parse("type:bogus")
        XCTAssertNil(q.kinds)
        XCTAssertFalse(q.onlySecrets)
        XCTAssertEqual(q.text, "type:bogus")           // fuzzy, not a filter
    }
}
