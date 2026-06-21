import Foundation

/// Parses the palette search box into structured filters so power users can scope
/// results: `type:link`, `type:secret`, `is:fav`, and a `/regex/` mode — all composable
/// with the remaining free-text fuzzy match (e.g. `type:link react`). Plain queries
/// behave exactly as before (fuzzy over the whole clip). Pure + testable.
struct SearchQuery {
    var kinds: Set<ClipKind>? = nil      // type:link / type:file / …
    var onlyFavorites = false            // is:fav
    var onlySecrets = false              // type:secret / is:secret (live detection, works on old clips)
    var regex: NSRegularExpression? = nil  // /pattern/  (case-insensitive)
    var text = ""                        // leftover fuzzy text

    /// type: aliases → the kind(s) they match.
    private static let kindMap: [String: Set<ClipKind>] = [
        "link": [.link], "url": [.link],
        "code": [.code],
        "color": [.color],
        "sha": [.gitSHA], "gitsha": [.gitSHA], "commit": [.gitSHA],
        "issue": [.issueKey], "ticket": [.issueKey],
        "file": [.file, .fileRef], "path": [.file, .fileRef],
        "snippet": [.snippet],
        "text": [.text],
        "image": [.image],
    ]

    /// Guards against a pathological user `/regex/` freezing the UI thread. It's the user's
    /// own pattern on their own clips (not untrusted input), so these caps are belt-and-braces.
    private static let maxRegexPattern = 130
    private static let maxRegexInput = 4000

    static func parse(_ raw: String) -> SearchQuery {
        var q = SearchQuery()
        var textTokens: [String] = []
        var usedOperator = false
        for token in raw.split(separator: " ") {
            let t = String(token)
            let lower = t.lowercased()
            if lower.hasPrefix("type:") {
                let v = String(lower.dropFirst("type:".count))
                if v == "secret" { q.onlySecrets = true; usedOperator = true }
                else if let ks = kindMap[v] { q.kinds = (q.kinds ?? []).union(ks); usedOperator = true }
                else { textTokens.append(t) }   // unknown type: → treat as literal text
            } else if lower == "is:fav" || lower == "is:favorite" {
                q.onlyFavorites = true; usedOperator = true
            } else if lower == "is:secret" {
                q.onlySecrets = true; usedOperator = true
            } else {
                textTokens.append(t)
            }
        }
        // With no operators, preserve the raw string verbatim so plain search is byte-for-byte
        // the old fuzzyMatch(query, text) path (no whitespace collapsing).
        let text = usedOperator ? textTokens.joined(separator: " ") : raw
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.count >= 2, trimmed.count <= maxRegexPattern, trimmed.hasPrefix("/"), trimmed.hasSuffix("/") {
            let pattern = String(trimmed.dropFirst().dropLast())
            q.regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            if q.regex == nil { q.text = text }   // invalid regex → fall back to literal fuzzy
        } else {
            q.text = text   // (an over-long /…/ also falls through to literal fuzzy)
        }
        return q
    }

    /// True if no filters and no text — the palette can skip filtering entirely.
    var isEmpty: Bool {
        kinds == nil && !onlyFavorites && !onlySecrets && regex == nil && text.isEmpty
    }

    func matches(_ item: ClipItem) -> Bool {
        if let kinds {
            // Match the stored kind OR the live-detected kind, so `type:link`/`type:file`
            // also find clips captured before type detection existed (stored as .text).
            if !kinds.contains(item.kind), !kinds.contains(ClipKind.detect(from: item.text)) { return false }
        }
        if onlyFavorites, !item.isFavorite { return false }
        if onlySecrets, !SecretDetector.isSecret(item.text) { return false }
        if let regex {
            let s = item.text.count > Self.maxRegexInput ? String(item.text.prefix(Self.maxRegexInput)) : item.text
            let range = NSRange(s.startIndex..., in: s)
            return regex.firstMatch(in: s, range: range) != nil
        }
        return fuzzyMatch(text, item.text)
    }
}
