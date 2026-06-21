import Foundation

/// The context-aware "act on this clip" behavior (⌘O in the palette), distinct from
/// ⏎-paste. Derived **live from the clip text** — not the stored `ClipKind` — so it also
/// works on clips captured before type detection existed. Only the config-free cases live
/// here; opening a commit/issue/editor (which needs a configured remote/tracker/editor) is
/// deferred. Every action is user-initiated and side-effect-light: reveal, open a web URL,
/// or reveal a file in Finder (never execute anything).
enum ClipAction: Equatable {
    case revealSecret            // temporarily unmask a masked secret in the list
    case openURL(URL)            // open an http/https link in the default browser
    case revealInFinder(URL)     // show an existing local file/path in Finder

    /// Short verb shown in the ⌘O hint.
    var label: String {
        switch self {
        case .revealSecret: return "reveal"
        case .openURL: return "open link"
        case .revealInFinder: return "reveal in Finder"
        }
    }

    /// The action for a clip, or nil if none applies. Pure except for a filesystem
    /// existence check on file paths (so we only offer "reveal" for files that exist).
    static func of(_ text: String) -> ClipAction? {
        if SecretDetector.isSecret(text) { return .revealSecret }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(where: \.isWhitespace) else { return nil }
        if let url = httpURL(t) { return .openURL(url) }
        if let file = existingFileURL(t) { return .revealInFinder(file) }
        return nil
    }

    /// Only http/https (and bare `www.`), never file:/javascript:/custom schemes.
    private static func httpURL(_ t: String) -> URL? {
        let s = t.lowercased().hasPrefix("www.") ? "https://" + t : t
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false else { return nil }
        return url
    }

    /// An absolute or `~`-rooted path that exists on disk, with an optional trailing
    /// `:line[:col]` (stack-trace form) stripped. Relative paths can't be resolved without
    /// a working directory, so they're skipped.
    private static func existingFileURL(_ t: String) -> URL? {
        let path = t.replacingOccurrences(of: #"(:[0-9]+){1,2}$"#, with: "", options: .regularExpression)
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/"), FileManager.default.fileExists(atPath: expanded) else { return nil }
        return URL(fileURLWithPath: expanded)
    }
}
