import XCTest
@testable import Mimer

/// Content-aware formatting inside the preview card. The rule these guard: the card may
/// re-*wrap* a clip, never re-*write* it, and it never colours something it hasn't identified.
final class ClipSyntaxTests: XCTestCase {

    // MARK: - Detection

    func testDiffDetection() {
        let patch = """
        @@ -1,4 +1,4 @@ func hover()
        -    old()
        +    new()
        """
        XCTAssertTrue(ClipSyntax.looksLikeDiff(patch))
        XCTAssertTrue(ClipSyntax.looksLikeDiff("diff --git a/x.swift b/x.swift\nindex 1..2 100644"))
        XCTAssertFalse(ClipSyntax.looksLikeDiff("a - b\na + b"), "arithmetic is not a patch")
        XCTAssertFalse(ClipSyntax.looksLikeDiff("one line"))
    }

    func testJSONDetection() {
        XCTAssertTrue(ClipSyntax.isJSON(#"{"a":1}"#))
        XCTAssertTrue(ClipSyntax.isJSON("  [1, 2, 3] "))
        XCTAssertFalse(ClipSyntax.isJSON(#"{"a":}"#))
        XCTAssertFalse(ClipSyntax.isJSON("42"), "a bare scalar isn't a JSON clip")
    }

    func testFormatPrefersContentOverStoredKind() {
        XCTAssertEqual(ClipSyntax.format(for: #"{"a":1}"#, kind: .text), .json(reindented: false))
        XCTAssertEqual(ClipSyntax.format(for: "https://x.com", kind: .link), .url)
        XCTAssertEqual(ClipSyntax.format(for: "let x = 1", kind: .code), .code)
        XCTAssertEqual(ClipSyntax.format(for: "just words", kind: .text), .plain)
    }

    // MARK: - JSON re-indent (whitespace only)

    func testReindentKeepsEveryTokenAndTheirOrder() throws {
        let raw = #"{"b":1,"a":[2,3],"c":{"d":"x, y"}}"#
        let out = try XCTUnwrap(ClipSyntax.reindentJSON(raw))
        XCTAssertTrue(out.contains("\n"))
        XCTAssertEqual(out.filter { !$0.isWhitespace }, raw.filter { !$0.isWhitespace },
                       "re-indenting must not add, drop, or reorder a single token")
        XCTAssertLessThan(out.range(of: "\"b\"")!.lowerBound, out.range(of: "\"a\"")!.lowerBound,
                          "key order is the clip's, not a dictionary's")
    }

    func testReindentLeavesStringsAlone() throws {
        let out = try XCTUnwrap(ClipSyntax.reindentJSON(#"{"path":"a/b: c,d {e}"}"#))
        XCTAssertTrue(out.contains(#""a/b: c,d {e}""#), "punctuation inside a string is content, not structure")
    }

    func testAlreadyFormattedJSONIsLeftAlone() {
        XCTAssertNil(ClipSyntax.reindentJSON("{\n  \"a\": 1\n}"))
        XCTAssertNil(ClipSyntax.reindentJSON("not json"))
    }

    func testEmptyContainersStayClosedUp() throws {
        let out = try XCTUnwrap(ClipSyntax.reindentJSON(#"{"a":{},"b":[]}"#))
        XCTAssertTrue(out.contains("{}"))
        XCTAssertTrue(out.contains("[]"))
    }

    // MARK: - Spans

    private func styles(_ text: String, _ format: ClipSyntax.Format) -> [(String, ClipSyntax.Style)] {
        let characters = Array(text)
        return ClipSyntax.spans(for: text, format: format).map {
            (String(characters[$0.range]), $0.style)
        }
    }

    func testDiffSpansMarkEachLineByItsRole() {
        let patch = """
        diff --git a/x b/x
        @@ -1 +1 @@
        -old
        +new
         same
        """
        let byStyle = Dictionary(grouping: styles(patch, .diff), by: \.1).mapValues { $0.map(\.0) }
        XCTAssertEqual(byStyle[.meta], ["diff --git a/x b/x"])
        XCTAssertEqual(byStyle[.hunk], ["@@ -1 +1 @@"])
        XCTAssertEqual(byStyle[.removed], ["-old"])
        XCTAssertEqual(byStyle[.added], ["+new"])
        XCTAssertNil(byStyle[.plain], "context lines carry no colour")
    }

    func testCodeSpansCoverCommentsStringsNumbersAndKeywords() {
        let found = styles(#"let x = "hi" // done"#, .code)
        XCTAssertTrue(found.contains { $0 == ("let", .keyword) })
        XCTAssertTrue(found.contains { $0 == (#""hi""#, .string) })
        XCTAssertTrue(found.contains { $0 == ("// done", .comment) })
    }

    func testStringFollowedByColonReadsAsAKey() {
        let found = styles(#"{"name": "Ada", "n": 42}"#, .json(reindented: false))
        XCTAssertTrue(found.contains { $0 == (#""name""#, .jsonKey) })
        XCTAssertTrue(found.contains { $0 == (#""Ada""#, .string) })
        XCTAssertTrue(found.contains { $0 == ("42", .number) })
    }

    func testCommentMarkersInsideAStringAreNotComments() {
        let found = styles(#"url = "https://example.com/a" + x"#, .code)
        XCTAssertTrue(found.contains { $0.1 == .string && $0.0.contains("https://") })
        XCTAssertFalse(found.contains { $0.1 == .comment })
    }

    func testURLSpansPickOutTheHostAndTheTrackingJunk() {
        let url = "https://mimer.hasanjafri.com/compare?utm_source=news&plan=pro&fbclid=abc"
        let found = styles(url, .url)
        XCTAssertTrue(found.contains { $0 == ("https://", .meta) })
        XCTAssertTrue(found.contains { $0 == ("mimer.hasanjafri.com", .host) })
        XCTAssertTrue(found.contains { $0 == ("utm_source=news", .tracking) })
        XCTAssertTrue(found.contains { $0 == ("fbclid=abc", .tracking) })
        XCTAssertFalse(found.contains { $0.0.contains("plan=pro") && $0.1 == .tracking },
                       "a real query parameter is not tracking")
    }

    func testTrackingParameterNames() {
        XCTAssertTrue(ClipSyntax.isTrackingParameter("utm_campaign"))
        XCTAssertTrue(ClipSyntax.isTrackingParameter("FBCLID"))
        XCTAssertFalse(ClipSyntax.isTrackingParameter("page"))
    }

    func testSpansStayInsideTheText() {
        for format in [ClipSyntax.Format.code, .diff, .url, .json(reindented: true)] {
            for text in ["", "x", "\n\n", #"{"a":"#, "https://", "// unterminated \"string"] {
                for span in ClipSyntax.spans(for: text, format: format) {
                    XCTAssertGreaterThanOrEqual(span.range.lowerBound, 0, "\(format) on \(text.debugDescription)")
                    XCTAssertLessThanOrEqual(span.range.upperBound, text.count, "\(format) on \(text.debugDescription)")
                }
            }
        }
    }
}

/// The one-glance badge in the card header.
final class ClipInspectorBadgeTests: XCTestCase {
    func testDiffBadgeCountsTheChange() {
        let patch = "@@ -1,2 +1,3 @@\n-gone\n+one\n+two\n context"
        XCTAssertEqual(ClipInspector.badge(for: patch, format: .diff), "+2 −1")
    }

    func testFormattedJSONSaysSo() {
        XCTAssertEqual(ClipInspector.badge(for: #"{"a":1}"#, format: .json(reindented: true)), "formatted")
        XCTAssertNil(ClipInspector.badge(for: "{\n\"a\": 1\n}", format: .json(reindented: false)))
    }

    func testTrackingParametersAreCounted() {
        let url = "https://x.com/a?utm_source=n&plan=pro&fbclid=z"
        XCTAssertEqual(ClipInspector.trackingParameterCount(in: url), 2)
        XCTAssertEqual(ClipInspector.badge(for: url, format: .url), "2 tracking params")
        XCTAssertNil(ClipInspector.badge(for: "https://x.com/a?plan=pro", format: .url))
    }

    func testMinifiedJSONClipIsFormattedAndTitledForWhatItIs() {
        let item = ClipItem(id: UUID(), text: #"{"a":1,"b":[2,3]}"#, kind: .text,
                            createdAt: Date(), isFavorite: false)
        let inspector = ClipInspector.make(for: item, maskSecrets: true)
        XCTAssertEqual(inspector.title, "JSON")
        XCTAssertEqual(inspector.badge, "formatted")
        guard case .text(let preview) = inspector.content else { return XCTFail("JSON renders as text") }
        XCTAssertTrue(preview.head.contains("\n"), "the card shows it wrapped")
        XCTAssertTrue(preview.monospaced)
    }

    func testASecretIsNeverSyntaxHighlightedIntoTheOpen() {
        let item = ClipItem(id: UUID(), text: #"{"aws_secret_access_key":"wJalrXUtnFEMI/K7MDENG/bPxRfiCY"}"#,
                            kind: .text, createdAt: Date(), isFavorite: false)
        let inspector = ClipInspector.make(for: item, maskSecrets: true)
        if case .masked = inspector.content {
            XCTAssertEqual(inspector.format, .plain, "masked content is never lexed")
        }
    }
}
