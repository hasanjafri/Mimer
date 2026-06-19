import Foundation

/// Case-insensitive subsequence match: every character of `query` appears in
/// `text` in order (e.g. "fpst" matches "func paste()"). Empty query matches all.
/// Strictly better than substring for a keyboard-driven palette; cheap enough to
/// run over the in-memory projection per keystroke at clipboard-history scale.
func fuzzyMatch(_ query: String, _ text: String) -> Bool {
    if query.isEmpty { return true }
    let needle = Array(query.lowercased())
    var i = 0
    for ch in text.lowercased() {
        if i < needle.count && ch == needle[i] {
            i += 1
            if i == needle.count { return true }
        }
    }
    return i == needle.count
}
