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

    static func parse(_ raw: String) -> SearchQuery {
        var q = SearchQuery()
        var textTokens: [String] = []
        for token in raw.split(separator: " ") {
            let t = String(token)
            let lower = t.lowercased()
            if lower.hasPrefix("type:") {
                let v = String(lower.dropFirst("type:".count))
                if v == "secret" { q.onlySecrets = true }
                else if let ks = kindMap[v] { q.kinds = (q.kinds ?? []).union(ks) }
                else { textTokens.append(t) }   // unknown type: → treat as literal text
            } else if lower == "is:fav" || lower == "is:favorite" {
                q.onlyFavorites = true
            } else if lower == "is:secret" {
                q.onlySecrets = true
            } else {
                textTokens.append(t)
            }
        }
        let text = textTokens.joined(separator: " ")
        if text.count >= 2, text.hasPrefix("/"), text.hasSuffix("/") {
            let pattern = String(text.dropFirst().dropLast())
            q.regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            if q.regex == nil { q.text = text }   // invalid regex → fall back to literal fuzzy
        } else {
            q.text = text
        }
        return q
    }

    /// True if no filters and no text — the palette can skip filtering entirely.
    var isEmpty: Bool {
        kinds == nil && !onlyFavorites && !onlySecrets && regex == nil && text.isEmpty
    }

    func matches(_ item: ClipItem) -> Bool {
        if let kinds, !kinds.contains(item.kind) { return false }
        if onlyFavorites, !item.isFavorite { return false }
        if onlySecrets, !SecretDetector.isSecret(item.text) { return false }
        if let regex {
            let range = NSRange(item.text.startIndex..., in: item.text)
            return regex.firstMatch(in: item.text, range: range) != nil
        }
        return fuzzyMatch(text, item.text)
    }
}
