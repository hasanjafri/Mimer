import XCTest
@testable import Mimer

final class ClipActionTests: XCTestCase {
    func testSecretWins() {
        // Built from parts so no real-looking secret literal is committed.
        XCTAssertEqual(ClipAction.of("AKIA" + "0123456789ABCDEF"), .revealSecret)
    }

    func testOpensOnlyHTTPLinks() {
        if case .openURL(let u)? = ClipAction.of("https://example.com/x?y=1") {
            XCTAssertEqual(u.absoluteString, "https://example.com/x?y=1")
        } else { XCTFail("https should open") }
        if case .openURL(let u)? = ClipAction.of("www.example.com") {
            XCTAssertEqual(u.scheme, "https")   // bare www gets https://
        } else { XCTFail("www should open") }

        // Non-web / unsafe schemes never open.
        XCTAssertNil(ClipAction.of("ftp://host/file"))
        XCTAssertNil(ClipAction.of("file:///etc/passwd"))
        XCTAssertNil(ClipAction.of("javascript:alert(1)"))
    }

    func testRevealsExistingFileStrippingLineCol() {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipaction-\(UUID().uuidString).txt")
        try? "x".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        for input in [file.path, file.path + ":42", file.path + ":42:7"] {
            if case .revealInFinder(let u)? = ClipAction.of(input) {
                XCTAssertEqual(u.path, file.path, "stack-trace :line:col should be stripped")
            } else { XCTFail("existing file should be revealable: \(input)") }
        }
    }

    func testRevealsFilePathWithSpaces() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip action \(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("My File.txt")
        try? "x".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        if case .revealInFinder(let u)? = ClipAction.of(file.path) {
            XCTAssertEqual(u.path, file.path)
        } else { XCTFail("a path with spaces should reveal") }
    }

    func testNoActionCases() {
        XCTAssertNil(ClipAction.of("just a sentence"))
        XCTAssertNil(ClipAction.of(""))
        XCTAssertNil(ClipAction.of("line one\nline two"))                      // multi-line ≠ single entity
        XCTAssertNil(ClipAction.of("/no/such/path/\(UUID().uuidString).txt"))  // doesn't exist
        XCTAssertNil(ClipAction.of("relative/path.txt"))                       // not absolute → unresolvable
    }
}
