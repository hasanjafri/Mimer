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
        ClipTransform(id: "iso2epoch", name: "ISO 8601 → Unix time", systemImage: "clock.arrow.circlepath") { isoToUnix($0) }
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
}
