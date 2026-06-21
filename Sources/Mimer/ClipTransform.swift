import Foundation

/// A named text transform offered via the palette's ⌘K actions. `apply` returns
/// nil when the transform doesn't apply to the input (JSON pretty-print on
/// non-JSON, base64 decode on non-base64, …) so the UI can hide it.
struct ClipTransform: Identifiable {
    let id: String
    let name: String
    let systemImage: String
    let apply: (String) -> String?

    /// Transforms that produce a different, non-empty result for `text`.
    static func applicable(to text: String) -> [ClipTransform] {
        all.compactMap { t in
            guard let out = t.apply(text), !out.isEmpty, out != text else { return nil }
            return t
        }
    }

    static let all: [ClipTransform] = [
        ClipTransform(id: "upper", name: "UPPERCASE", systemImage: "characters.uppercase") { $0.uppercased() },
        ClipTransform(id: "lower", name: "lowercase", systemImage: "characters.lowercase") { $0.lowercased() },
        ClipTransform(id: "title", name: "Title Case", systemImage: "textformat") { titleCase($0) },
        ClipTransform(id: "trim", name: "Trim whitespace", systemImage: "wand.and.stars") {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        },
        ClipTransform(id: "slug", name: "Slugify", systemImage: "link") { slugify($0) },
        ClipTransform(id: "b64enc", name: "Base64 encode", systemImage: "lock") {
            Data($0.utf8).base64EncodedString()
        },
        ClipTransform(id: "b64dec", name: "Base64 decode", systemImage: "lock.open") {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isLikelyBase64(trimmed), let d = Data(base64Encoded: trimmed) else { return nil }
            return String(data: d, encoding: .utf8)
        },
        ClipTransform(id: "urlenc", name: "URL encode", systemImage: "percent") {
            $0.addingPercentEncoding(withAllowedCharacters: urlComponentAllowed)
        },
        ClipTransform(id: "urldec", name: "URL decode", systemImage: "percent") { $0.removingPercentEncoding },
        ClipTransform(id: "jsonpretty", name: "JSON pretty-print", systemImage: "curlybraces") { jsonReformat($0, pretty: true) },
        ClipTransform(id: "jsonmin", name: "JSON minify", systemImage: "curlybraces") { jsonReformat($0, pretty: false) },
        // Developer transforms (each gated so it only appears when it actually applies).
        ClipTransform(id: "jwt", name: "Decode JWT", systemImage: "key") { decodeJWT($0) },
        ClipTransform(id: "urlstrip", name: "Strip tracking params", systemImage: "scissors") { stripTrackingParams($0) },
        ClipTransform(id: "urlquery", name: "Decode query string", systemImage: "list.bullet") { decodeQueryString($0) },
        ClipTransform(id: "epoch2iso", name: "Unix time → ISO 8601", systemImage: "clock") { unixToISO($0) },
        ClipTransform(id: "iso2epoch", name: "ISO 8601 → Unix time", systemImage: "clock.arrow.circlepath") { isoToUnix($0) },
        ClipTransform(id: "json2ts", name: "JSON → TypeScript", systemImage: "curlybraces.square") { jsonToTypeScript($0) },
        ClipTransform(id: "sortlines", name: "Sort lines A→Z", systemImage: "arrow.up.arrow.down") { sortLines($0) },
        ClipTransform(id: "dedupelines", name: "Dedupe lines", systemImage: "line.3.horizontal.decrease") { dedupeLines($0) },
        ClipTransform(id: "reverselines", name: "Reverse lines", systemImage: "arrow.uturn.up") { reverseLines($0) },
        ClipTransform(id: "camel", name: "camelCase", systemImage: "textformat.abc") { camelCase($0) },
        ClipTransform(id: "snake", name: "snake_case", systemImage: "textformat.abc") { snakeCase($0) }
    ]

    // MARK: - Helpers

    /// RFC 3986 unreserved set — percent-encode everything else (encodeURIComponent-like),
    /// so `&`, `=`, `?`, spaces, etc. are all escaped.
    private static let urlComponentAllowed = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func titleCase(_ s: String) -> String {
        s.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            guard let first = word.first else { return String(word) }
            return first.uppercased() + word.dropFirst()   // upcase first letter, leave the rest (keeps "iPhone", "don't")
        }.joined(separator: " ")
    }

    /// Conservative "looks like base64" gate so the decode action isn't offered on
    /// ordinary short words (e.g. "test"): base64 alphabet, padded length ≥ 8.
    private static func isLikelyBase64(_ s: String) -> Bool {
        guard s.count >= 8, s.count % 4 == 0 else { return false }
        return s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "/" || $0 == "=" }
    }

    private static func slugify(_ s: String) -> String {
        let chars = s.lowercased().unicodeScalars.map { sc -> Character in
            CharacterSet.alphanumerics.contains(sc) ? Character(sc) : "-"
        }
        return String(chars).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
    }

    /// Reformat only real JSON (top-level object/array — no fragments), so the
    /// action stays hidden for ordinary prose and numbers.
    private static func jsonReformat(_ s: String, pretty: Bool) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8)) else { return nil }
        var options: JSONSerialization.WritingOptions = [.withoutEscapingSlashes]
        if pretty { options.insert(.prettyPrinted); options.insert(.sortedKeys) }
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: options) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Developer transforms

    /// Decode a JWT's header + payload (the signature is binary, omitted). Returns nil
    /// unless it's a real JWT: three dot-separated base64url segments whose first two
    /// decode to JSON — so it never fires on ordinary dotted text.
    private static func decodeJWT(_ s: String) -> String? {
        let parts = s.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let header = base64urlJSON(parts[0]),
              let payload = base64urlJSON(parts[1]) else { return nil }
        return "// header\n\(header)\n\n// payload\n\(payload)"
    }

    /// A base64url segment → pretty-printed JSON, or nil if it isn't valid JSON.
    private static func base64urlJSON(_ seg: Substring) -> String? {
        var b64 = String(seg).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data),
              obj is [String: Any],   // JWT header/payload are JSON objects, not arrays/scalars
              let pretty = try? JSONSerialization.data(withJSONObject: obj,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return String(data: pretty, encoding: .utf8)
    }

    private static let trackingParams: Set<String> = [
        "gclid", "fbclid", "gbraid", "wbraid", "msclkid", "yclid", "dclid",
        "mc_eid", "mc_cid", "igshid", "ref", "ref_src", "ref_url", "_hsenc", "_hsmi", "vero_id"
    ]

    /// Parse only a real http/https URL (exact scheme, non-empty host) so the URL
    /// transforms don't fire on `httpx://…` or a bare `foo?bar=baz`.
    private static func httpURLComponents(_ s: String) -> URLComponents? {
        guard let c = URLComponents(string: s.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = c.scheme?.lowercased(), scheme == "http" || scheme == "https",
              c.host?.isEmpty == false else { return nil }
        return c
    }

    /// Remove common tracking params (utm_*, gclid, fbclid, …) from an http(s) URL.
    /// Returns nil for non-URLs or when nothing would be stripped, so it stays hidden.
    private static func stripTrackingParams(_ s: String) -> String? {
        guard var comps = httpURLComponents(s), let items = comps.queryItems else { return nil }
        let kept = items.filter { item in
            let name = item.name.lowercased()
            return !name.hasPrefix("utm_") && !trackingParams.contains(name)
        }
        guard kept.count != items.count else { return nil }   // nothing stripped → don't offer
        comps.queryItems = kept.isEmpty ? nil : kept
        return comps.string
    }

    /// List an http(s) URL's query parameters one per line (`name = value`).
    private static func decodeQueryString(_ s: String) -> String? {
        guard let comps = httpURLComponents(s), let items = comps.queryItems, !items.isEmpty else { return nil }
        return items.map { "\($0.name) = \($0.value ?? "")" }.joined(separator: "\n")
    }

    /// A Unix timestamp → ISO-8601 UTC. 9–10 digits = seconds (≈1973–2286),
    /// 12–13 = milliseconds. Gated on digit count so it doesn't fire on arbitrary numbers.
    private static func unixToISO(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.allSatisfy(\.isNumber), let n = Double(t) else { return nil }
        let seconds: Double
        switch t.count {
        case 9, 10:  seconds = n
        case 12, 13: seconds = n / 1000
        default:     return nil
        }
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: seconds))
    }

    /// An ISO-8601 datetime → Unix seconds. Tries plain then fractional-second parsing,
    /// so `…:22Z` and `…:22.123Z` both work. Gated on a successful ISO parse.
    private static func isoToUnix(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = plain.date(from: t) ?? fractional.date(from: t) else { return nil }
        return String(Int(date.timeIntervalSince1970))
    }

    // MARK: - Structure transforms

    /// Generate a TypeScript `interface Root { … }` from a top-level JSON object (nested
    /// objects inline). Returns nil for non-object JSON or non-JSON, so it stays hidden.
    /// Bounded by input size and recursion depth so a huge/deep clip can't stall the palette.
    private static func jsonToTypeScript(_ s: String) -> String? {
        guard s.utf8.count <= 200_000,
              let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] else { return nil }
        return "interface Root " + tsObject(obj, indent: 0, depth: 0)
    }

    private static let tsMaxDepth = 32

    private static func tsObject(_ obj: [String: Any], indent: Int, depth: Int) -> String {
        guard !obj.isEmpty else { return "{}" }
        guard depth < tsMaxDepth else { return "any" }
        let pad = String(repeating: "  ", count: indent + 1)
        let close = String(repeating: "  ", count: indent)
        let body = obj.keys.sorted().map { key -> String in
            let k = isTSIdentifier(key) ? key : tsStringLiteral(key)
            return "\(pad)\(k): \(tsType(obj[key]!, indent: indent + 1, depth: depth + 1));"
        }.joined(separator: "\n")
        return "{\n\(body)\n\(close)}"
    }

    private static func tsType(_ value: Any, indent: Int, depth: Int) -> String {
        if depth >= tsMaxDepth { return "any" }
        if value is NSNull { return "null" }
        if let n = value as? NSNumber { return CFGetTypeID(n) == CFBooleanGetTypeID() ? "boolean" : "number" }
        if value is String { return "string" }
        if let arr = value as? [Any] {
            guard !arr.isEmpty else { return "any[]" }
            // Union across a sample of elements, so [1,"x"] → (number | string)[], not number[].
            let types = Set(arr.prefix(50).map { tsType($0, indent: indent, depth: depth + 1) }).sorted()
            let union = types.joined(separator: " | ")
            return types.count == 1 ? "\(union)[]" : "(\(union))[]"
        }
        if let obj = value as? [String: Any] { return tsObject(obj, indent: indent, depth: depth + 1) }
        return "any"
    }

    private static func isTSIdentifier(_ s: String) -> Bool {
        s.range(of: #"^[A-Za-z_$][A-Za-z0-9_$]*$"#, options: .regularExpression) != nil
    }

    /// A fully-escaped double-quoted string literal for non-identifier keys. Uses JSON string
    /// encoding (escapes `\`, `"`, `\n`, `\r`, `\t`, and other controls as `\uXXXX`) — a valid
    /// JSON string is a valid TS string literal — so keys with newlines/controls stay valid TS.
    private static func tsStringLiteral(_ s: String) -> String {
        if let data = try? JSONSerialization.data(withJSONObject: [s]),
           let arr = String(data: data, encoding: .utf8), arr.count >= 2 {
            return String(arr.dropFirst().dropLast())   // ["..."] → "..."
        }
        return "\"" + s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t") + "\""
    }

    // MARK: - Line transforms (multi-line only, so they stay hidden for single-line clips)

    /// Apply `op` to the logical lines, ignoring a single trailing newline (so `"x\n"` reads
    /// as one line → hidden) and restoring it afterward. Returns nil for <2 logical lines.
    private static func lineOp(_ s: String, _ op: ([String]) -> [String]) -> String? {
        let hadTrailingNewline = s.hasSuffix("\n")
        let body = hadTrailingNewline ? String(s.dropLast()) : s
        let lines = body.components(separatedBy: "\n")
        guard lines.count >= 2 else { return nil }
        let out = op(lines).joined(separator: "\n")
        return hadTrailingNewline ? out + "\n" : out
    }

    private static func sortLines(_ s: String) -> String? {
        lineOp(s) { $0.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending } }
    }

    private static func dedupeLines(_ s: String) -> String? {
        lineOp(s) { lines in var seen = Set<String>(); return lines.filter { seen.insert($0).inserted } }
    }

    private static func reverseLines(_ s: String) -> String? {
        lineOp(s) { $0.reversed() }
    }

    // MARK: - Case transforms (identifier-like phrases only, so they stay off prose)

    /// Split an identifier-ish phrase into words on separators AND camelCase/acronym boundaries
    /// (`parseURLValue` → parse·URL·Value). nil (→ hidden) unless it's a short single line of
    /// letters/digits/`_-`+spaces that looks like an identifier — multi-word prose is rejected.
    private static func identifierWords(_ s: String) -> [String]? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains("\n"), t.count <= 60,
              t.allSatisfy({ $0.isLetter || $0.isNumber || $0 == " " || $0 == "_" || $0 == "-" }) else { return nil }

        let chars = Array(t)
        var words: [String] = []
        var cur = ""
        for (i, ch) in chars.enumerated() {
            if ch == " " || ch == "_" || ch == "-" {
                if !cur.isEmpty { words.append(cur); cur = "" }
                continue
            }
            if let prev = cur.last {
                let nextLower = i + 1 < chars.count && chars[i + 1].isLowercase
                if ch.isUppercase, prev.isLowercase || prev.isNumber {
                    words.append(cur); cur = ""                       // camelCase boundary
                } else if ch.isUppercase, prev.isUppercase, nextLower {
                    words.append(cur); cur = ""                       // acronym→word boundary (URLValue → URL·Value)
                }
            }
            cur.append(ch)
        }
        if !cur.isEmpty { words.append(cur) }
        guard !words.isEmpty else { return nil }

        // Prose guard: if the splitter found no more words than plain space-splitting would
        // (i.e. no `_`/`-`/camel/acronym signal — just separate words) and there are >3 of
        // them, treat it as prose, not an identifier (e.g. "This is just prose") and hide.
        let spaceWords = t.split(separator: " ", omittingEmptySubsequences: true).count
        if words.count <= spaceWords && words.count > 3 { return nil }
        return words
    }

    private static func camelCase(_ s: String) -> String? {
        guard let w = identifierWords(s) else { return nil }
        let head = w[0].lowercased()
        let tail = w.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
        return ([head] + tail).joined()
    }

    private static func snakeCase(_ s: String) -> String? {
        guard let w = identifierWords(s) else { return nil }
        return w.map { $0.lowercased() }.joined(separator: "_")
    }
}
