import Foundation

/// Content-aware styling for the preview body: the card shows a diff as a diff, JSON as JSON,
/// and a URL with its host picked out — because *what* a clip is, is half of telling two clips
/// apart. Pure and offset-based (character offsets, not String.Index) so it is trivially
/// testable and cheap to paint.
///
/// Deliberately a lexer, not a parser: it never rewrites the clip (the one exception is
/// re-indenting minified JSON, which is a whitespace-only pass over the same tokens and is
/// labelled "formatted" in the card). What you see is what you paste.
enum ClipSyntax {

    /// How a clip's body should be read. Detected from the text, not from the stored kind.
    enum Format: Equatable, Sendable {
        case plain
        case code
        case json(reindented: Bool)
        case diff
        case url
    }

    enum Style: Equatable, Sendable {
        case plain, comment, string, number, keyword, jsonKey
        case added, removed, hunk, meta
        case host, tracking
    }

    struct Span: Equatable, Sendable {
        var range: Range<Int>       // character offsets into the previewed text
        var style: Style
    }

    // MARK: - Detection

    static func format(for text: String, kind: ClipKind) -> Format {
        if kind == .link { return .url }
        if looksLikeDiff(text) { return .diff }
        if isJSON(text) { return .json(reindented: false) }
        if kind == .code { return .code }
        return .plain
    }

    /// A unified diff / patch: hunk headers plus +/- lines, or git's own header.
    static func looksLikeDiff(_ text: String) -> Bool {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 2 else { return false }
        if lines[0].hasPrefix("diff --git ") { return true }
        let hunk = lines.contains { $0.hasPrefix("@@") && $0.dropFirst(2).contains("@@") }
        let changes = lines.contains { $0.hasPrefix("+") } && lines.contains { $0.hasPrefix("-") }
        return hunk && changes
    }

    static func isJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[", trimmed.count <= 100_000 else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil
    }

    /// Re-indent minified JSON. A whitespace-only pass over the same characters — key order and
    /// every value survive byte-for-byte, unlike a decode/re-encode round trip. nil when the
    /// clip isn't minified JSON (already-formatted JSON is left exactly as it is).
    static func reindentJSON(_ text: String, indent: String = "  ") -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isJSON(trimmed), !trimmed.contains("\n"), trimmed.count <= 20_000 else { return nil }

        var out = ""
        var depth = 0
        var inString = false
        var escaped = false

        func newline(_ level: Int) {
            out.append("\n")
            out.append(String(repeating: indent, count: max(0, level)))
        }

        for character in trimmed {
            if inString {
                out.append(character)
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                continue
            }
            switch character {
            case "\"": inString = true; out.append(character)
            case "{", "[": depth += 1; out.append(character); newline(depth)
            case "}", "]": depth -= 1; newline(depth); out.append(character)
            case ",": out.append(character); newline(depth)
            case ":": out.append(character); out.append(" ")
            case " ", "\t", "\n": break            // token separators are rebuilt, not preserved
            default: out.append(character)
            }
        }
        // Empty containers read better closed up than spread over three lines.
        for pattern in [#"\{\n\s*\}"#: "{}", #"\[\n\s*\]"#: "[]"] {
            out = out.replacingOccurrences(of: pattern.key, with: pattern.value, options: .regularExpression)
        }
        return out
    }

    // MARK: - Spans

    static func spans(for text: String, format: Format) -> [Span] {
        switch format {
        case .plain: return []
        case .diff: return diffSpans(text)
        case .url: return urlSpans(text)
        case .code, .json: return codeSpans(text)
        }
    }

    /// One span per line, keyed off the leading marker — the shape everyone already reads.
    private static func diffSpans(_ text: String) -> [Span] {
        var spans: [Span] = []
        var offset = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let length = line.count
            let style: Style?
            if line.hasPrefix("@@") { style = .hunk }
            else if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") || line.hasPrefix("index ") { style = .meta }
            else if line.hasPrefix("+") { style = .added }
            else if line.hasPrefix("-") { style = .removed }
            else { style = nil }
            if let style, length > 0 { spans.append(Span(range: offset..<(offset + length), style: style)) }
            offset += length + 1        // + the newline
        }
        return spans
    }

    /// Scheme dimmed, host emphasised, and tracking parameters called out — the parts that
    /// actually distinguish two long URLs from each other.
    private static func urlSpans(_ text: String) -> [Span] {
        let characters = Array(text)
        var spans: [Span] = []

        var cursor = 0
        if let schemeEnd = indexOf("://", in: characters, from: 0) {
            spans.append(Span(range: 0..<(schemeEnd + 3), style: .meta))
            cursor = schemeEnd + 3
        }
        let hostEnd = [indexOf("/", in: characters, from: cursor),
                       indexOf("?", in: characters, from: cursor),
                       indexOf("#", in: characters, from: cursor)]
            .compactMap { $0 }.min() ?? characters.count
        if hostEnd > cursor { spans.append(Span(range: cursor..<hostEnd, style: .host)) }

        guard let queryStart = indexOf("?", in: characters, from: hostEnd) else { return spans }
        spans.append(Span(range: queryStart..<characters.count, style: .meta))

        // Each tracking parameter on top of the dimmed query, so it reads as removable noise.
        var paramStart = queryStart + 1
        while paramStart < characters.count {
            let end = indexOf("&", in: characters, from: paramStart) ?? characters.count
            let name = String(characters[paramStart..<min(end, characters.count)])
                .split(separator: "=", maxSplits: 1).first.map(String.init) ?? ""
            if isTrackingParameter(name) {
                spans.append(Span(range: paramStart..<end, style: .tracking))
            }
            paramStart = end + 1
        }
        return spans
    }

    static let trackingParameters: Set<String> = [
        "fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid", "igshid", "twclid",
        "yclid", "_hsenc", "_hsmi", "vero_id", "wickedid", "ref_src", "s_kwcid"
    ]

    static func isTrackingParameter(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasPrefix("utm_") || trackingParameters.contains(lower)
    }

    /// A small, language-agnostic lexer: comments, strings, numbers, keywords, and JSON keys.
    /// Wrong-language keywords are simply not highlighted — never mis-highlighted — because the
    /// only thing worse than no colour is colour that lies about what the code says.
    private static func codeSpans(_ text: String) -> [Span] {
        let c = Array(text)
        var spans: [Span] = []
        var i = 0

        while i < c.count {
            let ch = c[i]

            // Line comments: //, #, --  (# only at the start of a line, so it can't eat a fragment)
            if ch == "/" && i + 1 < c.count && c[i + 1] == "/"
                || ch == "-" && i + 1 < c.count && c[i + 1] == "-"
                || ch == "#" && isLineStart(c, i) {
                let end = indexOf("\n", in: c, from: i) ?? c.count
                spans.append(Span(range: i..<end, style: .comment))
                i = end
                continue
            }
            // Block comments
            if ch == "/" && i + 1 < c.count && c[i + 1] == "*" {
                var end = i + 2
                while end + 1 < c.count, !(c[end] == "*" && c[end + 1] == "/") { end += 1 }
                end = min(end + 2, c.count)
                spans.append(Span(range: i..<end, style: .comment))
                i = end
                continue
            }
            // Strings — a JSON/object key is a string followed by a colon, and reads better as a key
            if ch == "\"" || ch == "'" || ch == "`" {
                var end = i + 1
                while end < c.count {
                    if c[end] == "\\" { end += 2; continue }
                    if c[end] == ch { end += 1; break }
                    end += 1
                }
                end = min(end, c.count)
                var next = end
                while next < c.count, c[next] == " " { next += 1 }
                let isKey = next < c.count && c[next] == ":"
                spans.append(Span(range: i..<end, style: isKey ? .jsonKey : .string))
                i = end
                continue
            }
            // Numbers (not inside an identifier)
            if ch.isNumber, !isIdentifierCharacter(i > 0 ? c[i - 1] : " ") {
                var end = i
                while end < c.count, c[end].isHexDigit || c[end] == "." || c[end] == "x" || c[end] == "_" { end += 1 }
                spans.append(Span(range: i..<end, style: .number))
                i = end
                continue
            }
            // Identifiers → keywords
            if isIdentifierCharacter(ch), !ch.isNumber {
                var end = i
                while end < c.count, isIdentifierCharacter(c[end]) { end += 1 }
                if keywords.contains(String(c[i..<end])) {
                    spans.append(Span(range: i..<end, style: .keyword))
                }
                i = end
                continue
            }
            i += 1
        }
        return spans
    }

    private static func isLineStart(_ c: [Character], _ i: Int) -> Bool {
        var j = i - 1
        while j >= 0, c[j] == " " || c[j] == "\t" { j -= 1 }
        return j < 0 || c[j] == "\n"
    }

    private static func isIdentifierCharacter(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber || ch == "_" || ch == "$"
    }

    private static func indexOf(_ needle: Character, in c: [Character], from: Int) -> Int? {
        guard from < c.count else { return nil }
        return c[from...].firstIndex(of: needle)
    }

    private static func indexOf(_ needle: String, in c: [Character], from: Int) -> Int? {
        let pattern = Array(needle)
        guard c.count >= pattern.count else { return nil }
        var i = from
        while i <= c.count - pattern.count {
            if Array(c[i..<(i + pattern.count)]) == pattern { return i }
            i += 1
        }
        return nil
    }

    /// The union of the keyword sets a developer's clipboard actually holds. Shared words only —
    /// anything ambiguous (`type`, `object`, `name`) is left out on purpose.
    static let keywords: Set<String> = [
        // control flow / declarations, common across C-likes, Swift, Python, Go, Rust, Ruby
        "if", "else", "elif", "for", "while", "do", "switch", "case", "default", "break",
        "continue", "return", "yield", "await", "async", "try", "catch", "except", "finally",
        "throw", "throws", "raise", "guard", "defer", "match", "loop",
        "func", "function", "def", "fn", "class", "struct", "enum", "protocol", "interface",
        "extension", "impl", "trait", "module", "namespace", "package", "import", "from",
        "export", "require", "include", "use", "using", "let", "var", "const", "val", "static",
        "public", "private", "protected", "internal", "final", "abstract", "override", "new",
        "self", "this", "super", "nil", "null", "None", "true", "false", "True", "False",
        "int", "string", "bool", "float", "double", "void", "any", "unknown", "never",
        // SQL — clipboards are full of it
        "SELECT", "FROM", "WHERE", "JOIN", "LEFT", "INNER", "OUTER", "GROUP", "ORDER", "BY",
        "LIMIT", "OFFSET", "INSERT", "UPDATE", "DELETE", "VALUES", "SET", "AND", "OR", "NOT",
        "AS", "ON", "WITH", "UNION", "HAVING", "DISTINCT"
    ]
}
