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
        ClipTransform(id: "jsonmin", name: "JSON minify", systemImage: "curlybraces") { jsonReformat($0, pretty: false) }
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
}
