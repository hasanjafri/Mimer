import XCTest
@testable import Mimer

/// The spans a format produces, as (text, style) pairs — the readable form for assertions.
private func styledSpans(_ text: String, _ format: ClipSyntax.Format) -> [(String, ClipSyntax.Style)] {
    let characters = Array(text)
    return ClipSyntax.spans(for: text, format: format).map { (String(characters[$0.range]), $0.style) }
}

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
        styledSpans(text, format)
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
        let item = ClipItem(id: UUID(), text: "AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCY",
                            kind: .text, createdAt: Date(), isFavorite: false)
        let inspector = ClipInspector.make(for: item, maskSecrets: true)
        guard case .masked(let shown) = inspector.content else {
            return XCTFail("a detected secret must render masked, whatever its content shape")
        }
        XCTAssertFalse(shown.contains("wJalrXUtnFEMI"))
        XCTAssertEqual(inspector.format, .plain, "masked content is never lexed")
    }

    func testOneSidedHunksAreStillDiffs() {
        XCTAssertTrue(ClipSyntax.looksLikeDiff("@@ -1,0 +1,2 @@\n+added\n+more"), "add-only patch")
        XCTAssertTrue(ClipSyntax.looksLikeDiff("@@ -1,2 +1,0 @@\n-gone\n-also gone"), "delete-only patch")
        XCTAssertFalse(ClipSyntax.looksLikeDiff("@@ nothing @@\n context only"))
    }

    /// Headers precede the hunk they describe, and on their own they are not a change — a patch
    /// needs at least one added or removed line to be worth colouring as one.
    func testFileHeadersAloneAreNotAChange() {
        XCTAssertFalse(ClipSyntax.looksLikeDiff("--- a/x\n+++ b/x\n@@ -1 +1 @@"))
        XCTAssertEqual(ClipInspector.badge(for: "--- a/x\n+++ b/x\n@@ -1 +1 @@", format: .diff), nil)
    }

    /// A patch whose only change is a line that *looks* like a header — `+---` (a Markdown rule),
    /// or a removed line whose own text began with `-- ` — is still a patch. Position decides:
    /// after a hunk header, `---` is content.
    func testMarkerShapedContentIsStillAChange() {
        XCTAssertTrue(ClipSyntax.looksLikeDiff("@@ -1,0 +1 @@\n+---"))
        XCTAssertTrue(ClipSyntax.looksLikeDiff("@@ -1 +1,0 @@\n----"))
        XCTAssertTrue(ClipSyntax.looksLikeDiff("@@ -1,0 +1 @@\n+++ still content"))
    }

    func testMarkerShapedContentKeepsItsColour() {
        let patch = "@@ -1,3 +1,3 @@\n+---\n--- a/x\n+++ b/x"
        let found = styledSpans(patch, .diff)
        XCTAssertTrue(found.contains { $0 == ("+---", .added) })
        XCTAssertTrue(found.contains { $0 == ("--- a/x", .removed) },
                      "after a hunk header this is a removed line whose text is '-- a/x'")
        XCTAssertTrue(found.contains { $0 == ("+++ b/x", .added) })
    }

    /// The elided *tail* of a long patch has no hunk header of its own — it must still read as
    /// changes, not as metadata. This is the part the preview card exists to show.
    func testTheTailOfALongDiffKeepsItsColours() {
        let tail = "+        watchdog.start()\n-        watchdog.stop()\n         return true"
        let byStyle = Dictionary(grouping: styledSpans(tail, .diff), by: \.1).mapValues { $0.count }
        XCTAssertEqual(byStyle[.added], 1)
        XCTAssertEqual(byStyle[.removed], 1)
        XCTAssertNil(byStyle[.meta], "a mid-hunk fragment has no headers in it")
    }

    func testAHeaderOnlyFragmentStillReadsAsHeaders() {
        let head = "diff --git a/x b/x\nindex 1111111..2222222 100644"
        let byStyle = Dictionary(grouping: styledSpans(head, .diff), by: \.1).mapValues { $0.count }
        XCTAssertEqual(byStyle[.meta], 2)
    }

    func testRealFileHeadersAreMetadata() {
        let patch = """
        diff --git a/x b/x
        index 1111111..2222222 100644
        --- a/x
        +++ b/x
        @@ -1 +1 @@
        -old
        +new
        """
        let byStyle = Dictionary(grouping: styledSpans(patch, .diff), by: \.1).mapValues { $0.map(\.0) }
        XCTAssertEqual(byStyle[.meta], ["diff --git a/x b/x", "index 1111111..2222222 100644", "--- a/x", "+++ b/x"])
        XCTAssertEqual(byStyle[.removed], ["-old"])
        XCTAssertEqual(byStyle[.added], ["+new"])
        XCTAssertEqual(ClipInspector.badge(for: patch, format: .diff), "+1 −1",
                       "the badge counts the same roles the colouring uses")
    }

    func testHeadersOfASecondFileAreStillHeaders() {
        let patch = """
        diff --git a/x b/x
        --- a/x
        +++ b/x
        @@ -1 +1 @@
        -one
        diff --git a/y b/y
        --- a/y
        +++ b/y
        @@ -1 +1 @@
        +two
        """
        XCTAssertEqual(ClipInspector.badge(for: patch, format: .diff), "+1 −1",
                       "the second file's headers must not be counted as changes")
    }

    func testPercentEncodedTrackingNamesMatchTheTransform() {
        let url = "https://x.com/a?utm%5Fsource=news&keep=1"
        let found = styledSpans(url, .url)
        XCTAssertTrue(found.contains { $0.1 == .tracking && $0.0.contains("utm%5Fsource") },
                      "⌘K sees the decoded name, so the card must too")
        XCTAssertEqual(ClipInspector.trackingParameterCount(in: url), 1, "and the badge agrees")
    }

    /// The badge must state the number the card actually highlights. Asserted against the badge
    /// *string* — comparing `trackingParameterCount` to the spans would just re-run its own
    /// definition and could never fail.
    func testBadgeStatesWhatTheCardHighlights() {
        let cases = ["https://x.com/a?utm_source=n&plan=pro&fbclid=z": "2 tracking params",
                     "https://x.com/a?utm%5Fsource=n": "1 tracking param",
                     "https://x.com/a?utm_source=n#utm_source=notaparam": "1 tracking param",
                     "https://x.com/a?keep=1": nil,
                     "https://x.com/a": nil]
        for (url, expected) in cases {
            XCTAssertEqual(ClipInspector.badge(for: url, format: .url), expected, url)

            // …and the badge the card *renders* must equal the badge implied by the spans it
            // paints, built here independently of how the badge computes its number.
            let highlighted = styledSpans(url, .url).filter { $0.1 == .tracking }.count
            let impliedByHighlights = highlighted == 0
                ? nil
                : "\(highlighted) tracking param\(highlighted == 1 ? "" : "s")"
            XCTAssertEqual(ClipInspector.badge(for: url, format: .url), impliedByHighlights, url)
        }
    }

    func testFragmentsAreNotTracking() {
        let url = "https://example.com/docs?utm_source=news#installation"
        let found = ClipSyntax.spans(for: url, format: .url).map {
            (String(Array(url)[$0.range]), $0.style)
        }
        XCTAssertTrue(found.contains { $0 == ("utm_source=news", .tracking) })
        XCTAssertFalse(found.contains { $0.0.contains("#installation") },
                       "a fragment is neither query nor tracking noise")
    }

    func testTheElidedTailOfALongURLStillLexes() {
        // What the card actually renders for the tail of an elided URL: no scheme, no '?'.
        let tail = "utm_campaign=launch&plan=pro&fbclid=abc"
        let found = ClipSyntax.spans(for: tail, format: .url).map {
            (String(Array(tail)[$0.range]), $0.style)
        }
        XCTAssertFalse(found.contains { $0.1 == .host }, "a query fragment is not a host")
        XCTAssertTrue(found.contains { $0 == ("utm_campaign=launch", .tracking) })
        XCTAssertTrue(found.contains { $0 == ("fbclid=abc", .tracking) })
    }

    func testHostDetectionRejectsQueryLikeText() {
        XCTAssertTrue(ClipSyntax.looksLikeHost("sub.example.co.uk:8080"))
        XCTAssertFalse(ClipSyntax.looksLikeHost("utm_campaign=launch&plan=pro"))
        XCTAssertFalse(ClipSyntax.looksLikeHost("nodots"))
    }

    func testTrackingListIsSharedWithTheStripTransform() {
        // The badge counts what ⌘K would strip — one list, or the card lies.
        for name in ["gbraid", "wbraid", "utm_term", "fbclid"] {
            XCTAssertTrue(ClipSyntax.isTrackingParameter(name), name)
            XCTAssertTrue(ClipTransform.isTrackingParameter(name), name)
        }
        let url = "https://x.com/a?gbraid=1&wbraid=2&keep=3"
        XCTAssertEqual(ClipInspector.trackingParameterCount(in: url), 2)
        XCTAssertEqual(ClipTransform.all.first { $0.id == "urlstrip" }?.apply(url), "https://x.com/a?keep=3")
    }
}
