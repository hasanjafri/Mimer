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
    var appFilter: String? = nil         // app:<name> — case-insensitive substring of the source app
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

        // Pull a quoted multi-word app filter first: app:"Visual Studio Code".
        var rest = raw
        if let r = rest.range(of: #"app:"[^"]*""#, options: .regularExpression) {
            let value = String(rest[r].dropFirst("app:\"".count).dropLast())
            if !value.isEmpty { q.appFilter = value; usedOperator = true }
            rest.removeSubrange(r)
        }

        for token in rest.split(separator: " ") {
            let t = String(token)
            let lower = t.lowercased()
            if lower.hasPrefix("type:") {
                let v = String(lower.dropFirst("type:".count))
                if v == "secret" { q.onlySecrets = true; usedOperator = true }
                else if let ks = kindMap[v] { q.kinds = (q.kinds ?? []).union(ks); usedOperator = true }
                else { textTokens.append(t) }   // unknown type: → treat as literal text
            } else if lower.hasPrefix("app:") {
                var v = String(t.dropFirst("app:".count))   // original case; matched case-insensitively
                if v.hasPrefix("\"") { v.removeFirst() }    // strip stray quotes (e.g. a single-token app:"x")
                if v.hasSuffix("\"") { v.removeLast() }
                if v.isEmpty { textTokens.append(t) } else { q.appFilter = v; usedOperator = true }
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
            if !looksCatastrophic(pattern) {
                q.regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            }
            if q.regex == nil { q.text = text }   // invalid/risky regex → fall back to literal fuzzy
        } else {
            q.text = text   // (an over-long /…/ also falls through to literal fuzzy)
        }
        return q
    }

    /// Best-effort rejection of the classic exponential-backtracking shapes (a quantified
    /// group that itself contains a quantifier — `(a+)+`, `(.*)*`, `(x+){2,}`). NSRegularExpression
    /// has no timeout, and this filters runs on the main thread, so a risky pattern is treated
    /// as literal text instead. Not exhaustive — it's the user's own pattern on their own clips.
    private static func looksCatastrophic(_ pattern: String) -> Bool {
        pattern.range(of: #"\([^()]*[+*}][^()]*\)[*+{]"#, options: .regularExpression) != nil
    }

    /// True if no filters and no text — the palette can skip filtering entirely.
    var isEmpty: Bool {
        kinds == nil && !onlyFavorites && !onlySecrets && regex == nil && appFilter == nil && text.isEmpty
    }

    func matches(_ item: ClipItem) -> Bool {
        if let kinds {
            // Match the stored kind OR the live-detected kind, so `type:link`/`type:file`
            // also find clips captured before type detection existed (stored as .text).
            if !kinds.contains(item.kind), !kinds.contains(ClipKind.detect(from: item.text)) { return false }
        }
        if let appFilter {
            guard let app = item.sourceApp,
                  app.range(of: appFilter, options: .caseInsensitive) != nil else { return false }
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
