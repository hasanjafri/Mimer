import XCTest
@testable import Mimer

final class ClipActionTests: XCTestCase {
    func testSecretWins() {
        // Built from parts so no real-looking secret literal is committed.
        XCTAssertEqual(ClipAction.of("AKIA" + "0123456789ABCDEF"), .revealSecret)
    }

    func testOpensOnlyHTTPLinks() {
        if case .open(let u, "open link")? = ClipAction.of("https://example.com/x?y=1") {
            XCTAssertEqual(u.absoluteString, "https://example.com/x?y=1")
        } else { XCTFail("https should open") }
        if case .open(let u, "open link")? = ClipAction.of("www.example.com") {
            XCTAssertEqual(u.scheme, "https")   // bare www gets https://
        } else { XCTFail("www should open") }

        // Non-web / unsafe schemes never open.
        XCTAssertNil(ClipAction.of("ftp://host/file"))
        XCTAssertNil(ClipAction.of("file:///etc/passwd"))
        XCTAssertNil(ClipAction.of("javascript:alert(1)"))
    }

    func testGitSHAOpensCommitWhenRemoteConfigured() {
        let cfg = ClipAction.DevConfig(gitRemoteBase: "github.com/acme/app")
        if case .open(let u, "open commit")? = ClipAction.of("9f2a1c7", config: cfg) {
            XCTAssertEqual(u.absoluteString, "https://github.com/acme/app/commit/9f2a1c7")
        } else { XCTFail("git SHA should open a commit") }
        // Full URL + trailing slash + .git all normalize.
        if case .open(let u, _)? = ClipAction.of("9f2a1c7", config: ClipAction.DevConfig(gitRemoteBase: "https://gitlab.com/acme/app.git/")) {
            XCTAssertEqual(u.absoluteString, "https://gitlab.com/acme/app/commit/9f2a1c7")
        } else { XCTFail("normalized base should work") }
        XCTAssertNil(ClipAction.of("9f2a1c7"))   // no config → no action (SHA isn't a link/file)
    }

    func testCommitURLNormalization() {
        func commit(_ base: String) -> String? {
            if case .open(let u, _)? = ClipAction.of("9f2a1c7", config: ClipAction.DevConfig(gitRemoteBase: base)) {
                return u.absoluteString
            }
            return nil
        }
        XCTAssertEqual(commit("git@github.com:acme/app.git"), "https://github.com/acme/app/commit/9f2a1c7")  // scp SSH
        XCTAssertEqual(commit("https://github.com/acme/app/"), "https://github.com/acme/app/commit/9f2a1c7")  // trailing slash
        XCTAssertNil(commit("https://github.com/acme/app?x=1"))   // query would distort the path → rejected
        XCTAssertNil(commit("https://user@github.com/acme/app"))  // userinfo → rejected
    }

    func testIssueKeyOpensTrackerWhenConfigured() {
        let cfg = ClipAction.DevConfig(issueTrackerTemplate: "https://acme.atlassian.net/browse/{KEY}")
        if case .open(let u, "open issue")? = ClipAction.of("ABC-1234", config: cfg) {
            XCTAssertEqual(u.absoluteString, "https://acme.atlassian.net/browse/ABC-1234")
        } else { XCTFail("issue key should open the tracker") }
        // Template without {KEY} is treated as unset → no action.
        XCTAssertNil(ClipAction.of("ABC-1234", config: ClipAction.DevConfig(issueTrackerTemplate: "https://x/browse/")))
    }

    func testFileOpensEditorWhenConfigured() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipedit-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("Main.swift")
        try? "x".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let cfg = ClipAction.DevConfig(editor: .vscode)
        if case .open(let u, "open in editor")? = ClipAction.of(file.path + ":42:7", config: cfg) {
            XCTAssertEqual(u.scheme, "vscode")
            XCTAssertTrue(u.absoluteString.hasSuffix(":42:7"))
            XCTAssertTrue(u.absoluteString.contains("Main.swift"))
        } else { XCTFail("file:line should open in the editor when configured") }
        // A PLAIN file path (no line) reveals in Finder even with an editor configured.
        if case .revealInFinder? = ClipAction.of(file.path, config: cfg) {} else { XCTFail("plain path → Finder even with editor") }
        // No editor configured → Finder reveal.
        if case .revealInFinder? = ClipAction.of(file.path + ":42") {} else { XCTFail("no editor → Finder reveal") }
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
