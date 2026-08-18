import XCTest
@testable import Mimer

/// The hover preview card's content model. The rules that matter: a long clip keeps both its
/// start and its end, a masked secret stays masked, and the counts it reports are true.
final class ClipInspectorTests: XCTestCase {

    private func clip(_ text: String,
                      kind: ClipKind = .text,
                      favorite: Bool = false,
                      app: String? = nil,
                      created: Date = Date()) -> ClipItem {
        ClipItem(id: UUID(), text: text, kind: kind, createdAt: created,
                 isFavorite: favorite, sourceApp: app)
    }

    // MARK: - Preview / middle elision

    func testShortTextIsShownWhole() {
        let preview = ClipInspector.preview("hello world", monospaced: false)
        XCTAssertEqual(preview.head, "hello world")
        XCTAssertEqual(preview.tail, "")
        XCTAssertEqual(preview.elided, 0)
        XCTAssertFalse(preview.isElided)
    }

    func testLongSingleLineKeepsHeadAndTail() {
        let text = String(repeating: "a", count: 3000) + "TAIL"
        let preview = ClipInspector.preview(text, monospaced: false, charBudget: 1200, lineBudget: 20)

        XCTAssertTrue(preview.isElided)
        XCTAssertTrue(text.hasPrefix(preview.head), "head must be a real prefix of the clip")
        XCTAssertTrue(text.hasSuffix(preview.tail), "tail must be a real suffix — the end is what disambiguates")
        XCTAssertTrue(preview.tail.hasSuffix("TAIL"))
        XCTAssertEqual(preview.head.count + preview.tail.count + preview.elided, text.count,
                       "the elided count must account for exactly what is hidden")
    }

    func testLongMultiLineKeepsFirstAndLastLines() {
        let text = (1...40).map { "line \($0)" }.joined(separator: "\n")
        let preview = ClipInspector.preview(text, monospaced: true, charBudget: 1200, lineBudget: 20)

        XCTAssertTrue(preview.isElided)
        XCTAssertTrue(preview.head.hasPrefix("line 1\n"))
        XCTAssertTrue(preview.tail.hasSuffix("line 40"))
        XCTAssertEqual(preview.head.split(separator: "\n").count, 14)
        XCTAssertEqual(preview.tail.split(separator: "\n").count, 6)
    }

    /// Head + tail must never overlap into duplicated content — if they'd cover the whole clip,
    /// show it whole instead of claiming an elision.
    func testBudgetsThatCoverEverythingShowTheWholeClip() {
        let text = (1...10).map { "line \($0)" }.joined(separator: "\n")
        let preview = ClipInspector.preview(text, monospaced: true, charBudget: 5000, lineBudget: 20)
        XCTAssertEqual(preview.head, text)
        XCTAssertEqual(preview.elided, 0)
    }

    /// Hiding one line behind a "1 more line" marker saves nothing — a little slack over
    /// budget is the better trade.
    func testASliverIsShownRatherThanElided() {
        let text = (1...21).map { "line \($0)" }.joined(separator: "\n")
        let preview = ClipInspector.preview(text, monospaced: true, charBudget: 5000, lineBudget: 20)
        XCTAssertEqual(preview.head, text)
        XCTAssertEqual(preview.elided, 0)
    }

    func testTrailingBlankLinesAreTrimmedFromThePreview() {
        let preview = ClipInspector.preview("body\n\n\n", monospaced: false)
        XCTAssertEqual(preview.head, "body")
    }

    // MARK: - Fragment context

    /// The tail is the only shown slice with text before it, and lexing it alone gets it wrong.
    /// Here the tail opens *inside* a string literal: on its own the lexer reads the closing
    /// quote as an opener and paints everything after it; with context it sees the string end.
    func testTailIsLexedWithTheTextBeforeIt() {
        let filler = String(repeating: "let x = 1\n", count: 120)
        let display = ClipInspector.displayText(filler + "let b = \"AAAABBBBCCCC\" trailing")
        let tail = String(display.suffix(18))          // BBBBCCCC" trailing
        XCTAssertTrue(tail.hasPrefix("BBBBCCCC\""), "tail must open inside the literal")

        let alone = ClipSyntax.spans(for: tail, format: .code)
        let withContext = ClipInspector.tailSpans(display, tail: tail, format: .code)

        XCTAssertEqual(withContext.first?.range.lowerBound, 0, "the tail begins inside the string")
        XCTAssertEqual(withContext.first?.range.upperBound, 9, "which ends at its closing quote")
        XCTAssertEqual(withContext.first?.style, .string)
        XCTAssertFalse(withContext.contains { $0.range.contains(12) }, "'trailing' is code, not string")

        XCTAssertNotEqual(alone, withContext)
        XCTAssertTrue(alone.contains { $0.range.contains(12) },
                      "lexed alone it swallows the rest — the bug this closes")
    }

    func testTailSpansAreEmptyWithoutATail() {
        XCTAssertTrue(ClipInspector.tailSpans("whole clip", tail: "", format: .code).isEmpty)
    }

    /// The head begins where the clip begins, so it needs no context — the model must still
    /// hand the card spans for it.
    func testBothShownSlicesCarrySpans() {
        let code = (1...60).map { "let value\($0) = \"string \($0)\"  // note \($0)" }.joined(separator: "\n")
        let item = clip(code, kind: .code)
        guard case .text(let preview) = ClipInspector.make(for: item, maskSecrets: true).content else {
            return XCTFail("expected a text preview")
        }
        XCTAssertTrue(preview.isElided)
        XCTAssertFalse(preview.headSpans.isEmpty)
        XCTAssertFalse(preview.tailSpans.isEmpty)
        XCTAssertTrue(preview.headSpans.allSatisfy { $0.range.upperBound <= preview.head.count })
        XCTAssertTrue(preview.tailSpans.allSatisfy { $0.range.upperBound <= preview.tail.count })
    }

    // MARK: - Stats

    func testStatsCountCharactersWordsAndLines() {
        let stats = ClipInspector.stats(for: "one two\nthree")
        XCTAssertEqual(stats.first?.value, "13")
        XCTAssertEqual(stats.first?.label, "characters")
        XCTAssertEqual(stats.map(\.label), ["characters", "words", "lines"])
        XCTAssertEqual(stats[1].value, "3")
        XCTAssertEqual(stats[2].value, "2")
    }

    func testSingleLineOmitsTheLineCount() {
        XCTAssertEqual(ClipInspector.stats(for: "hello there").map(\.label), ["characters", "words"])
        XCTAssertEqual(ClipInspector.stats(for: "x").map(\.label), ["character"])
    }

    func testImageStats() {
        let stats = ClipInspector.imageStats(pixelWidth: 1284, pixelHeight: 860, byteCount: 2048, type: "PNG")
        XCTAssertEqual(stats.first?.value, "1284 × 860")
        XCTAssertTrue(stats.contains { $0.value == "PNG" })
    }

    // MARK: - Kind + title

    func testOldTextClipsGetTheirRealKindInTheCard() {
        // Captured before type detection existed → stored as .text, detected live here.
        let item = clip("https://example.com/a/b")
        XCTAssertEqual(ClipInspector.effectiveKind(of: item), .link)
        XCTAssertEqual(ClipInspector.make(for: item, maskSecrets: true).title, "Link")
    }

    func testStoredKindWins() {
        XCTAssertEqual(ClipInspector.effectiveKind(of: clip("anything", kind: .snippet)), .snippet)
        XCTAssertEqual(ClipInspector.title(for: .snippet, secretKind: nil), "Snippet")
    }

    func testSecretTitleNamesTheKindOfSecret() {
        let title = ClipInspector.make(for: clip("AKIAIOSFODNN7EXAMPLE"), maskSecrets: true).title
        XCTAssertEqual(title, "Secret · AWS key")
    }

    func testProseIsProportionalAndTokensAreMonospaced() {
        XCTAssertFalse(ClipInspector.prefersMonospace(.text, text: "a sentence of prose"))
        XCTAssertTrue(ClipInspector.prefersMonospace(.text, text: "single-token"))
        XCTAssertTrue(ClipInspector.prefersMonospace(.code, text: "let x = 1"))
    }

    // MARK: - Secrets

    func testMaskedSecretStaysMaskedInTheCard() {
        let item = clip("AKIAIOSFODNN7EXAMPLE")
        guard case .masked(let shown) = ClipInspector.make(for: item, maskSecrets: true).content else {
            return XCTFail("a detected secret must render masked, not as text")
        }
        XCTAssertFalse(shown.contains("AKIAIOSFODNN7EXAMPLE"))
        XCTAssertTrue(shown.contains("AWS key"))
    }

    func testRevealedSecretShowsItsText() {
        let item = clip("AKIAIOSFODNN7EXAMPLE")
        guard case .text(let preview) = ClipInspector.make(for: item, maskSecrets: true, revealed: true).content else {
            return XCTFail("⌘O-revealed secrets show their value")
        }
        XCTAssertEqual(preview.head, "AKIAIOSFODNN7EXAMPLE")
    }

    func testMaskingOffShowsTheText() {
        let item = clip("AKIAIOSFODNN7EXAMPLE")
        guard case .text = ClipInspector.make(for: item, maskSecrets: false).content else {
            return XCTFail("with masking off the card shows the value")
        }
    }

    // MARK: - Color

    func testColorContentCarriesTheSwatchValues() {
        guard case .color(let hex, let rgb) = ClipInspector.make(for: clip("#3B82F6", kind: .color),
                                                                 maskSecrets: true).content else {
            return XCTFail("a color clip renders as a swatch")
        }
        XCTAssertEqual(hex, "#3B82F6")
        XCTAssertEqual(rgb, "rgb(59, 130, 246)")
    }

    func testRGBLabel() {
        XCTAssertEqual(ClipInspector.rgbLabel("#fff"), "rgb(255, 255, 255)")
        XCTAssertEqual(ClipInspector.rgbLabel("#00000080"), "rgba(0, 0, 0, 0.50)")
        XCTAssertNil(ClipInspector.rgbLabel("not a color"))
    }

    // MARK: - Search highlighting

    func testHighlightRangesFindEveryLiteralMatch() {
        let text = "shipping ships shipped"
        let ranges = ClipInspector.highlightRanges(in: text, query: "ship")
        XCTAssertEqual(ranges.count, 3)
        XCTAssertEqual(text[ranges[0]], "ship")
    }

    func testHighlightIsCaseInsensitiveAndSkipsNoiseQueries() {
        XCTAssertEqual(ClipInspector.highlightRanges(in: "Hello", query: "hel").count, 1)
        XCTAssertTrue(ClipInspector.highlightRanges(in: "abc", query: "a").isEmpty, "one character matches everything")
        XCTAssertTrue(ClipInspector.highlightRanges(in: "abc", query: "/b/").isEmpty, "regex queries have no literal span")
    }

    func testHighlightIsBounded() {
        let text = String(repeating: "ab", count: 500)
        XCTAssertEqual(ClipInspector.highlightRanges(in: text, query: "ab", limit: 10).count, 10)
    }

    // MARK: - Metadata

    func testRecentClipsReadAsJustNow() {
        XCTAssertEqual(ClipInspector.relativeLabel(Date(), now: Date()), "just now")
    }

    /// A clip stamped in the future (clock skew, a restored database) is not "just now".
    func testFutureTimestampsAreNotJustNow() {
        let now = Date()
        XCTAssertNotEqual(ClipInspector.relativeLabel(now.addingTimeInterval(30), now: now), "just now")
    }

    /// A clip can match your search entirely inside the part the card elides — say so rather
    /// than showing a preview with no visible reason for being in the results.
    func testMatchesHiddenInTheElidedMiddleAreCounted() {
        let text = String(repeating: "a", count: 600) + " needle needle " + String(repeating: "b", count: 600)
        let item = clip(text)
        guard case .text(let preview) = ClipInspector.make(for: item, maskSecrets: true,
                                                           query: "needle").content else {
            return XCTFail("expected a text preview")
        }
        XCTAssertTrue(preview.isElided)
        XCTAssertEqual(preview.hiddenMatches, 2)
        XCTAssertFalse(preview.head.contains("needle"))
        XCTAssertFalse(preview.tail.contains("needle"))
    }

    /// The count must never be the cap dressed up as a real number.
    func testHiddenMatchCountIsCappedNotTruncatedSilently() {
        let middle = String(repeating: "needle ", count: 900)
        let item = clip(String(repeating: "a", count: 700) + " " + middle + String(repeating: "b", count: 700))
        guard case .text(let preview) = ClipInspector.make(for: item, maskSecrets: true,
                                                           query: "needle").content else {
            return XCTFail("expected a text preview")
        }
        XCTAssertEqual(preview.hiddenMatches, ClipInspector.hiddenMatchCap)
    }

    func testVisibleMatchesAreNotCountedAsHidden() {
        let item = clip("needle " + String(repeating: "a", count: 2000))
        guard case .text(let preview) = ClipInspector.make(for: item, maskSecrets: true,
                                                           query: "needle").content else {
            return XCTFail("expected a text preview")
        }
        XCTAssertTrue(preview.head.hasPrefix("needle"))
        XCTAssertEqual(preview.hiddenMatches, 0)
    }

    func testProvenanceAndFavoriteCarryThrough() {
        let item = clip("hi", favorite: true, app: "Safari")
        let inspector = ClipInspector.make(for: item, maskSecrets: true)
        XCTAssertEqual(inspector.sourceApp, "Safari")
        XCTAssertTrue(inspector.isFavorite)
        XCTAssertNil(inspector.actionHint)
    }

    func testActionHintComesFromTheClipAction() {
        let item = clip("https://example.com")
        let inspector = ClipInspector.make(for: item, maskSecrets: true,
                                           action: ClipAction.of(item.text))
        XCTAssertEqual(inspector.actionHint, "open link")
    }
}

/// Where the card lands: beside its host window, on screen, never covering the list.
final class ClipPeekLayoutTests: XCTestCase {
    private let screen = NSRect(x: 0, y: 0, width: 1600, height: 1000)
    private let size = NSSize(width: 380, height: 400)

    func testSitsToTheRightOfItsHost() {
        let host = NSRect(x: 480, y: 280, width: 640, height: 440)
        let frame = ClipPeekLayout.frame(size: size, host: host, pointer: NSPoint(x: 700, y: 500), visible: screen)
        XCTAssertEqual(frame.minX, host.maxX + 10)
        XCTAssertEqual(frame.midY, 500, accuracy: 0.5, "vertically centred on the anchor")
    }

    func testFlipsToTheLeftWhenTheRightEdgeIsFull() {
        let host = NSRect(x: 1100, y: 280, width: 480, height: 440)
        let frame = ClipPeekLayout.frame(size: size, host: host, pointer: NSPoint(x: 1300, y: 500), visible: screen)
        XCTAssertEqual(frame.maxX, host.minX - 10)
    }

    func testHugsTheEdgeWhenNeitherSideFits() {
        let small = NSRect(x: 0, y: 0, width: 800, height: 600)
        let host = NSRect(x: 0, y: 0, width: 800, height: 600)
        let frame = ClipPeekLayout.frame(size: size, host: host, pointer: NSPoint(x: 400, y: 300), visible: small)
        XCTAssertTrue(small.contains(frame), "the card is always fully on screen")
    }

    func testClampsToTheScreenVertically() {
        let host = NSRect(x: 480, y: 280, width: 640, height: 440)
        let high = ClipPeekLayout.frame(size: size, host: host, pointer: NSPoint(x: 700, y: 995), visible: screen)
        XCTAssertLessThanOrEqual(high.maxY, screen.maxY)
        let low = ClipPeekLayout.frame(size: size, host: host, pointer: NSPoint(x: 700, y: 2), visible: screen)
        XCTAssertGreaterThanOrEqual(low.minY, screen.minY)
    }

    func testFallsBackToThePointerWithNoHostWindow() {
        let frame = ClipPeekLayout.frame(size: size, host: nil, pointer: NSPoint(x: 200, y: 500), visible: screen)
        XCTAssertEqual(frame.minX, 216)
    }
}

extension ClipInspectorTests {
    /// A cut mid-word reads as damage; back it up to the nearest space when one is close.
    func testCutsLandOnWordBoundaries() {
        let text = String(repeating: "alpha bravo charlie ", count: 200)
        let preview = ClipInspector.preview(text, monospaced: false, charBudget: 300, lineBudget: 14)
        XCTAssertTrue(preview.isElided)
        XCTAssertFalse(preview.head.hasSuffix("alph"), "no dangling partial word at the cut")
        XCTAssertTrue(["alpha", "bravo", "charlie"].contains { preview.head.hasSuffix($0) })
        XCTAssertTrue(["alpha", "bravo", "charlie"].contains { preview.tail.hasPrefix($0) })
        XCTAssertEqual(preview.head.count + preview.tail.count + preview.elided, text.count - 1,
                       "the trailing space is trimmed for display; everything else is accounted for")
    }
}
