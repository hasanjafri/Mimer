import Foundation

/// The context-aware "act on this clip" behavior (⌘O in the palette), distinct from
/// ⏎-paste. Derived **live from the clip text** — not the stored `ClipKind` — so it also
/// works on clips captured before type detection existed. Config-free actions (reveal a
/// secret, open an http/https link, reveal a file in Finder) always work; the *integration*
/// actions (open a commit / issue / editor) appear only when the matching target is set in
/// Settings → Developer. Every action is user-initiated and side-effect-light — it opens a
/// URL or reveals a file, never executes anything.
enum ClipAction: Equatable {
    case revealSecret               // temporarily unmask a masked secret in the list
    case open(URL, label: String)   // open a URL: web link · commit · issue · editor (custom scheme)
    case revealInFinder(URL)        // show an existing local file in Finder

    var label: String {
        switch self {
        case .revealSecret: return "reveal"
        case .open(_, let label): return label
        case .revealInFinder: return "reveal in Finder"
        }
    }

    /// User-configured integration targets (from Settings → Developer). Empty/unset fields
    /// disable the corresponding action, so behaviour falls back to the config-free cases.
    struct DevConfig: Equatable {
        var gitRemoteBase: String? = nil        // "github.com/acme/app" or a full https URL
        var issueTrackerTemplate: String? = nil // e.g. "https://acme.atlassian.net/browse/{KEY}"
        var editor: Editor? = nil

        enum Editor: String, CaseIterable, Equatable {
            case vscode, cursor
            var scheme: String { rawValue }
            var displayName: String { self == .vscode ? "VS Code" : "Cursor" }
        }
    }

    /// The action for a clip, or nil if none applies. Pure except for a filesystem existence
    /// check on file paths (so we only offer file actions for files that exist).
    static func of(_ text: String, config: DevConfig = DevConfig()) -> ClipAction? {
        if SecretDetector.isSecret(text) { return .revealSecret }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(where: \.isNewline) else { return nil }   // single line only

        // Configurable integrations (only when their target is set).
        if let base = config.gitRemoteBase, ClipKind.detect(from: t) == .gitSHA,
           let u = commitURL(base, sha: t) { return .open(u, label: "open commit") }
        if let tpl = config.issueTrackerTemplate, ClipKind.detect(from: t) == .issueKey,
           let u = issueURL(tpl, key: t) { return .open(u, label: "open issue") }

        // Config-free: web links never contain raw spaces; file paths can.
        if !t.contains(" "), let url = httpURL(t) { return .open(url, label: "open link") }
        if let ref = parseFileRef(t) {
            if let editor = config.editor, let u = editorURL(editor, ref) { return .open(u, label: "open in editor") }
            return .revealInFinder(URL(fileURLWithPath: ref.path))
        }
        return nil
    }

    /// Only http/https (and bare `www.`), never file:/javascript:/custom schemes.
    private static func httpURL(_ t: String) -> URL? {
        let s = t.lowercased().hasPrefix("www.") ? "https://" + t : t
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host?.isEmpty == false else { return nil }
        return url
    }

    /// `{remoteBase}/commit/{sha}` as an https URL. Accepts a bare host/path or a full URL;
    /// strips a trailing slash and `.git`. (GitHub/GitLab use /commit/<sha>.)
    private static func commitURL(_ base: String, sha: String) -> URL? {
        var b = base.trimmingCharacters(in: .whitespaces)
        if !b.lowercased().hasPrefix("http") { b = "https://" + b }
        while b.hasSuffix("/") { b.removeLast() }
        if b.hasSuffix(".git") { b.removeLast(4) }
        guard let u = URL(string: b + "/commit/" + sha),
              let s = u.scheme?.lowercased(), s == "http" || s == "https", u.host?.isEmpty == false else { return nil }
        return u
    }

    /// Substitute `{KEY}` in the tracker template; require an http/https result.
    private static func issueURL(_ template: String, key: String) -> URL? {
        guard template.contains("{KEY}") else { return nil }
        let s = template.replacingOccurrences(of: "{KEY}", with: key)
        guard let u = URL(string: s), let scheme = u.scheme?.lowercased(),
              scheme == "http" || scheme == "https", u.host?.isEmpty == false else { return nil }
        return u
    }

    /// `vscode://file/{absPath}:{line}:{col}` (or cursor://). The path is percent-encoded so
    /// spaces are valid in the URL.
    private static func editorURL(_ editor: DevConfig.Editor, _ ref: FileRef) -> URL? {
        let encoded = ref.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ref.path
        var s = "\(editor.scheme)://file\(encoded)"
        if let line = ref.line { s += ":\(line)"; if let col = ref.col { s += ":\(col)" } }
        return URL(string: s)
    }

    private struct FileRef { let path: String; let line: Int?; let col: Int? }

    /// An absolute or `~`-rooted path that exists, with an optional trailing `:line[:col]`
    /// (stack-trace form) parsed off. Relative paths can't be resolved without a cwd → nil.
    private static func parseFileRef(_ t: String) -> FileRef? {
        var path = t
        var line: Int?, col: Int?
        if let m = t.range(of: #":[0-9]+(:[0-9]+)?$"#, options: .regularExpression) {
            let nums = t[m].dropFirst().split(separator: ":").compactMap { Int($0) }
            line = nums.first
            col = nums.count > 1 ? nums[1] : nil
            path = String(t[t.startIndex..<m.lowerBound])
        }
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/"), FileManager.default.fileExists(atPath: expanded) else { return nil }
        return FileRef(path: expanded, line: line, col: col)
    }
}
