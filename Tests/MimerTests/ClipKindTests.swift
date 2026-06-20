import XCTest
@testable import Mimer

final class ClipKindTests: XCTestCase {
    func testDetectsLinks() {
        XCTAssertEqual(ClipKind.detect(from: "https://example.com/x?y=1"), .link)
        XCTAssertEqual(ClipKind.detect(from: "www.example.com"), .link)
        XCTAssertEqual(ClipKind.detect(from: "ftp://host/file"), .link)
        XCTAssertEqual(ClipKind.detect(from: "x:://y"), .text)               // stray "://" is not a scheme
        XCTAssertEqual(ClipKind.detect(from: "git@github.com:foo/bar.git"), .text)
    }

    func testDetectsHexColors() {
        XCTAssertEqual(ClipKind.detect(from: "#1e90ff"), .color)
        XCTAssertEqual(ClipKind.detect(from: "#abc"), .color)
        XCTAssertEqual(ClipKind.detect(from: "#11223344"), .color)
        XCTAssertEqual(ClipKind.detect(from: "facade"), .text)   // no '#' → not a color
    }

    func testDetectsCode() {
        XCTAssertEqual(ClipKind.detect(from: "func greet() { print(\"hi\") }"), .code)
        XCTAssertEqual(ClipKind.detect(from: "const f = () => 1"), .code)
        XCTAssertEqual(ClipKind.detect(from: "<div class=\"x\"></div>"), .code)
        XCTAssertEqual(ClipKind.detect(from: "{\"a\":1,\"b\":2}"), .code)    // JSON keeps the code glyph
    }

    func testPlainText() {
        XCTAssertEqual(ClipKind.detect(from: "just a normal sentence"), .text)
        XCTAssertEqual(ClipKind.detect(from: "let me know when you're free"), .text)  // not code
        XCTAssertEqual(ClipKind.detect(from: "Hi {name}, welcome aboard"), .text)     // braces alone ≠ code
        XCTAssertEqual(ClipKind.detect(from: ""), .text)
    }
}
