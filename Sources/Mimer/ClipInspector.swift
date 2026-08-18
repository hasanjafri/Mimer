import Foundation

/// Everything the hover preview card shows for one clip, derived **purely** from the clip and
/// the display prefs — so the whole content model is unit-testable with no UI. `ClipInspectorCard`
/// only lays this out; `ClipPeek` decides when and where it appears.
///
/// Two rules it exists to enforce. A long clip is elided in the **middle**, never at the tail —
/// the ending is often the only thing telling two near-identical clips apart, which is exactly
/// when you reach for the preview. And a masked secret stays masked here: the card must not
/// become the shoulder-surf hole that row masking closes.
struct ClipInspector: Equatable, Sendable {
    var kind: ClipKind
    var title: String
    var format: ClipSyntax.Format
    var badge: String?              // "formatted" · "+12 −3" · "2 tracking params"
    var content: Content
    var stats: [Stat]
    var sourceApp: String?
    var relativeTime: String
    var absoluteTime: String
    var actionHint: String?
    var isFavorite: Bool
    /// The palette's search text, highlighted in the body by the card.
    var query: String = ""

    enum Content: Equatable, Sendable {
        case text(Preview)
        case masked(String)          // a detected secret, shown as its masked form
        case image(hash: String?)
        case color(hex: String, rgb: String?)
    }

    /// Head + tail of the clip with the middle elided.
    struct Preview: Equatable, Sendable {
        var head: String
        var tail: String
        var elided: Int              // characters hidden between head and tail (0 = the whole clip)
        var monospaced: Bool
        /// Search matches that fall inside the elided middle. Without this a clip could match
        /// your search entirely in the part the card doesn't show, with nothing to say so.
        var hiddenMatches: Int = 0
        var isElided: Bool { elided > 0 }
    }

    struct Stat: Equatable, Sendable, Identifiable {
        var value: String
        var label: String
        var id: String { label }
    }

    /// Budgets chosen so the tallest card still fits a laptop screen beside the palette.
    static let charBudget = 800
    static let lineBudget = 14
    /// Structured content (code, JSON, diffs) is denser and scanned line by line, so it earns
    /// more of both budgets than prose does.
    static let structuredCharBudget = 1100
    static let structuredLineBudget = 24
    /// Below this much hidden content, showing the clip whole beats eliding it.
    static let elisionSlack = 100

    static func make(for item: ClipItem,
                     maskSecrets: Bool,
                     revealed: Bool = false,
                     action: ClipAction? = nil,
                     query: String = "",
                     now: Date = Date()) -> ClipInspector {
        let secretKind = SecretDetector.kind(of: item.text)
        let kind = effectiveKind(of: item)
        var format = ClipSyntax.format(for: item.text, kind: kind)

        let content: Content
        if let secretKind, maskSecrets, !revealed {
            format = .plain
            content = .masked(SecretDetector.maskedPreview(item.text) ?? "\(secretKind) ••••")
        } else if kind == .image {
            format = .plain
            content = .image(hash: item.blobHash)
        } else if kind == .color {
            format = .plain
            let hex = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            content = .color(hex: hex, rgb: rgbLabel(hex))
        } else {
            // Minified JSON is unreadable at any width; re-indenting is a whitespace-only pass
            // over the same tokens, and the card labels it so nobody mistakes it for the clip.
            var body = item.text
            if case .json = format, let reindented = ClipSyntax.reindentJSON(item.text) {
                body = reindented
                format = .json(reindented: true)
            }
            let structured = format != .plain
            var text = preview(body,
                               monospaced: structured || prefersMonospace(kind, text: item.text),
                               charBudget: structured ? structuredCharBudget : charBudget,
                               lineBudget: structured ? structuredLineBudget : lineBudget)
            text.hiddenMatches = hiddenMatchCount(in: body, preview: text, query: query)
            content = .text(text)
        }

        return ClipInspector(
            kind: kind,
            title: title(for: kind, format: format, secretKind: secretKind),
            format: format,
            badge: badge(for: item.text, format: format),
            content: content,
            stats: stats(for: item.text),
            sourceApp: item.sourceApp.flatMap { $0.isEmpty ? nil : $0 },
            relativeTime: relativeLabel(item.createdAt, now: now),
            absoluteTime: absoluteLabel(item.createdAt, now: now),
            actionHint: action.map(\.label),
            isFavorite: item.isFavorite,
            query: query
        )
    }

    /// How many search matches are in the part of the clip the card doesn't show — the head is a
    /// prefix and the tail a suffix of the displayed text, so the middle is what's left.
    static func hiddenMatchCount(in body: String, preview: Preview, query: String) -> Int {
        guard preview.isElided, !query.isEmpty else { return 0 }
        let display = displayText(body)
        guard display.count > preview.head.count + preview.tail.count else { return 0 }
        let middle = display.dropFirst(preview.head.count).dropLast(preview.tail.count)
        return highlightRanges(in: String(middle), query: query).count
    }

    // MARK: - Kind

    /// Clips captured before type detection existed are stored as `.text`, so detect live for
    /// those — the detail card is where a stale label is most annoying. Mirrors `ClipAction`.
    static func effectiveKind(of item: ClipItem) -> ClipKind {
        item.kind == .text ? ClipKind.detect(from: item.text) : item.kind
    }

    static func title(for kind: ClipKind, format: ClipSyntax.Format = .plain, secretKind: String? = nil) -> String {
        if let secretKind { return "Secret · \(secretKind)" }
        if case .json = format { return "JSON" }
        if case .diff = format { return "Diff" }
        switch kind {
        case .text: return "Text"
        case .code: return "Code"
        case .link: return "Link"
        case .color: return "Color"
        case .image: return "Image"
        case .file: return "File"
        case .snippet: return "Snippet"
        case .gitSHA: return "Commit SHA"
        case .issueKey: return "Issue key"
        case .fileRef: return "File path"
        }
    }

    /// The one-glance summary of what makes this clip what it is: how much a diff changes, how
    /// much of a URL is tracking junk, whether the JSON on screen was re-wrapped for reading.
    static func badge(for text: String, format: ClipSyntax.Format) -> String? {
        switch format {
        case .json(let reindented):
            return reindented ? "formatted" : nil
        case .diff:
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            let added = lines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count
            let removed = lines.filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count
            guard added + removed > 0 else { return nil }
            return "+\(added) −\(removed)"
        case .url:
            let count = trackingParameterCount(in: text)
            guard count > 0 else { return nil }
            return count == 1 ? "1 tracking param" : "\(count) tracking params"
        case .code, .plain:
            return nil
        }
    }

    static func trackingParameterCount(in url: String) -> Int {
        guard let query = url.split(separator: "?", maxSplits: 1).dropFirst().first else { return 0 }
        return query.split(separator: "&")
            .map { $0.split(separator: "=", maxSplits: 1).first.map(String.init) ?? "" }
            .filter(ClipSyntax.isTrackingParameter)
            .count
    }

    /// Monospace anything structural — code, paths, tokens — but keep prose proportional so a
    /// paragraph still reads like a paragraph.
    static func prefersMonospace(_ kind: ClipKind, text: String) -> Bool {
        switch kind {
        case .code, .link, .gitSHA, .issueKey, .fileRef, .file, .color: return true
        case .text, .snippet, .image: return !text.contains(where: \.isWhitespace)
        }
    }

    // MARK: - Preview (middle elision)

    static func preview(_ raw: String,
                        monospaced: Bool,
                        charBudget: Int = ClipInspector.charBudget,
                        lineBudget: Int = ClipInspector.lineBudget) -> Preview {
        let text = displayText(raw)
        let lineCount = text.split(separator: "\n", omittingEmptySubsequences: false).count
        guard text.count > charBudget || lineCount > lineBudget else {
            return Preview(head: text, tail: "", elided: 0, monospaced: monospaced)
        }

        // Two thirds opening / one third ending: the start identifies the clip, the end
        // disambiguates the near-identical ones.
        let headChars = max(1, charBudget * 2 / 3)
        let tailChars = max(1, charBudget - headChars)
        let tailLines = max(1, lineBudget / 3)
        let headLines = max(1, lineBudget - tailLines)

        let head = limited(text, chars: headChars, lines: headLines, fromStart: true)
        let tail = limited(text, chars: tailChars, lines: tailLines, fromStart: false)

        // If the two halves already cover everything, show it whole rather than claim an elision.
        guard head.count + tail.count < text.count else {
            return Preview(head: text, tail: "", elided: 0, monospaced: monospaced)
        }
        // Eliding a sliver costs a marker line and buys nothing — allow a little slack over
        // budget instead, so a 21-line clip in a 20-line budget just shows all 21.
        let hidden = text.count - head.count - tail.count
        if hidden <= Self.elisionSlack, lineCount <= lineBudget + 2 {
            return Preview(head: text, tail: "", elided: 0, monospaced: monospaced)
        }
        return Preview(head: head, tail: tail, elided: hidden, monospaced: monospaced)
    }

    /// The leading (or trailing) slice of `text` within both a line and a character budget.
    private static func limited(_ text: String, chars: Int, lines: Int, fromStart: Bool) -> String {
        let parts = text.split(separator: "\n", omittingEmptySubsequences: false)
        var slice = fromStart
            ? parts.prefix(lines).joined(separator: "\n")
            : parts.suffix(lines).joined(separator: "\n")
        if slice.count > chars { slice = cut(slice, to: chars, fromStart: fromStart) }
        return fromStart
            ? String(slice.reversed().drop(while: \.isWhitespace).reversed())   // no dangling blank lines
            : slice
    }

    /// Take `chars` from one end, landing on a word boundary when one is within reach — a
    /// preview that ends (or starts) mid-word reads as damage rather than as an elision.
    private static func cut(_ s: String, to chars: Int, fromStart: Bool, window: Int = 40) -> String {
        if fromStart {
            let end = s.index(s.startIndex, offsetBy: chars)
            var boundary = end
            if !s[end].isWhitespace,
               let space = s[s.startIndex..<end].suffix(window).lastIndex(where: \.isWhitespace) {
                boundary = space
            }
            return String(s[s.startIndex..<boundary])
        }
        let start = s.index(s.endIndex, offsetBy: -chars)
        var boundary = start
        if !s[s.index(before: start)].isWhitespace,
           let space = s[start...].prefix(window).firstIndex(where: \.isWhitespace) {
            boundary = s.index(after: space)
        }
        return String(s[boundary...])
    }

    /// Trailing blank space is noise in a preview (many clips end with a newline); leading
    /// indentation is content, so it stays.
    static func displayText(_ raw: String) -> String {
        String(raw.reversed().drop(while: \.isWhitespace).reversed())
    }

    // MARK: - Stats

    static func stats(for text: String) -> [Stat] {
        let chars = text.count
        let words = text.split(whereSeparator: \.isWhitespace).count
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        var out = [Stat(value: chars.formatted(), label: chars == 1 ? "character" : "characters")]
        if words > 1 { out.append(Stat(value: words.formatted(), label: "words")) }
        if lines > 1 { out.append(Stat(value: lines.formatted(), label: "lines")) }
        return out
    }

    /// `1284 × 860 · PNG · 240 KB` for an image clip, assembled from what the blob itself says.
    static func imageStats(pixelWidth: Int?, pixelHeight: Int?, byteCount: Int, type: String?) -> [Stat] {
        var out: [Stat] = []
        if let pixelWidth, let pixelHeight, pixelWidth > 0, pixelHeight > 0 {
            out.append(Stat(value: "\(pixelWidth) × \(pixelHeight)", label: "px"))
        }
        if let type, !type.isEmpty { out.append(Stat(value: type, label: "")) }
        out.append(Stat(value: byteCount.formatted(.byteCount(style: .file)), label: ""))
        return out
    }

    // MARK: - Time

    static func relativeLabel(_ date: Date, now: Date = Date()) -> String {
        let delta = now.timeIntervalSince(date)
        if delta >= 0, delta < 60 { return "just now" }   // a future stamp (clock skew) reads as a real date
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// Today drops the date (the time is enough); older clips keep month + day.
    static func absoluteLabel(_ date: Date, now: Date = Date()) -> String {
        if Calendar.current.isDate(date, inSameDayAs: now) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    // MARK: - Color

    /// `#3B82F6` → `rgb(59, 130, 246)`; nil if it isn't a hex color. Alpha is appended only
    /// when the clip actually carries one.
    static func rgbLabel(_ hex: String) -> String? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 || s.count == 4 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        let shift = s.count == 8 ? 8 : 0
        let r = (value >> (16 + shift)) & 0xff
        let g = (value >> (8 + shift)) & 0xff
        let b = (value >> shift) & 0xff
        if s.count == 8 {
            let a = Double(value & 0xff) / 255
            return "rgba(\(r), \(g), \(b), \(String(format: "%.2f", a)))"
        }
        return "rgb(\(r), \(g), \(b))"
    }

    // MARK: - Search highlighting

    /// Ranges of `query` inside `text`, case-insensitively — the palette highlights its search
    /// term in the card so a match buried in the middle of a long clip is findable at a glance.
    /// Literal matches only: the palette's fuzzy (subsequence) matching has no contiguous range
    /// to point at, so those simply come back empty.
    static func highlightRanges(in text: String, query: String, limit: Int = 40) -> [Range<String.Index>] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard needle.count >= 2, !needle.hasPrefix("/") else { return [] }
        var ranges: [Range<String.Index>] = []
        var start = text.startIndex
        while ranges.count < limit,
              let found = text.range(of: needle, options: .caseInsensitive, range: start..<text.endIndex) {
            ranges.append(found)
            start = found.upperBound
            if start >= text.endIndex { break }
        }
        return ranges
    }
}
