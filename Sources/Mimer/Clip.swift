import CoreData

/// Kind of clip. Text is all v0 captures today; the rest are reserved so the
/// model, dedupe, and UI switch-points exist before the content lands (images,
/// code-aware clips, snippets, etc.) — avoids a migration later.
enum ClipKind: Int16 {
    case text = 0
    case code = 1
    case link = 2
    case color = 3
    case image = 4
    case file = 5
    case snippet = 6
    case gitSHA = 7
    case issueKey = 8
    case fileRef = 9
}

extension ClipKind {
    /// Best-effort classification for display (glyphs / treatment). Conservative:
    /// flags only high-confidence links, hex colors, and code — otherwise `.text`.
    static func detect(from raw: String) -> ClipKind {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .text }

        if !text.contains(where: \.isWhitespace) {
            let lower = text.lowercased()
            if lower.hasPrefix("www.") { return .link }
            // scheme://… with a real scheme (rejects stray "://" like "x:://y").
            if let r = lower.range(of: "://") {
                let scheme = lower[lower.startIndex..<r.lowerBound]
                if let first = scheme.first, first.isLetter,
                   scheme.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "." || $0 == "-" }) {
                    return .link
                }
            }
            if let dev = developerToken(text) { return dev }
        }
        if isHexColor(text) { return .color }
        if looksLikeCode(raw) { return .code }
        return .text
    }

    /// Single-token developer entities (conservative). The act-on behavior lives in
    /// `ClipAction`, computed live from text; this just drives the row icon for new captures.
    private static func developerToken(_ t: String) -> ClipKind? {
        if t.range(of: #"^[A-Z]{2,10}-[0-9]+$"#, options: .regularExpression) != nil { return .issueKey }
        // 7–40 hex with at least one a–f letter, so plain decimal numbers aren't "SHAs".
        if t.count >= 7, t.count <= 40,
           t.range(of: #"^[0-9a-f]+$"#, options: .regularExpression) != nil,
           t.contains(where: \.isLetter) { return .gitSHA }
        if isFileRef(t) { return .fileRef }
        return nil
    }

    private static func isFileRef(_ t: String) -> Bool {
        let path = t.replacingOccurrences(of: #"(:[0-9]+){1,2}$"#, with: "", options: .regularExpression)
        // A real path prefix, or a stack-trace "name.ext:line[:col]" (a :line was stripped).
        if path.hasPrefix("/") || path.hasPrefix("~/") || path.hasPrefix("./") || path.hasPrefix("../") { return true }
        if path != t, path.range(of: #"\.[A-Za-z0-9]{1,6}$"#, options: .regularExpression) != nil { return true }
        return false
    }

    private static func isHexColor(_ s: String) -> Bool {
        guard s.hasPrefix("#") else { return false }   // require '#' so words like "facade" aren't colors
        let hex = s.dropFirst()
        return [3, 4, 6, 8].contains(hex.count) && hex.allSatisfy(\.isHexDigit)
    }

    private static func looksLikeCode(_ s: String) -> Bool {
        // Braces, but require a corroborating signal so prose like "Hi {name}" isn't
        // flagged; JSON keeps its glyph via the `:"`-style signal.
        if s.contains("{"), s.contains("}"),
           s.contains(";") || s.contains("=") || s.contains("\n") || (s.contains(":") && s.contains("\"")) {
            return true
        }
        if s.contains("=>") || s.contains("</") || s.contains("/>") { return true }
        let starts = ["func ", "def ", "const ", "function ", "import ",
                      "#include", "package ", "<?xml", "<!DOCTYPE", "SELECT "]
        let head = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if starts.contains(where: { head.hasPrefix($0) }) { return true }
        // Multi-line with consistent indentation (≥2 indented lines).
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count >= 2, lines.filter({ $0.hasPrefix("  ") || $0.hasPrefix("\t") }).count >= 2 {
            return true
        }
        return false
    }
}

/// Persisted clipboard entry. Attributes are optional/defaulted; `contentHash`
/// drives kind-agnostic dedupe; `kind` discriminates content type.
@objc(Clip)
final class Clip: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var text: String?
    @NSManaged var contentHash: String?
    @NSManaged var kind: Int16
    @NSManaged var createdAt: Date?
    @NSManaged var lastUsedAt: Date?
    @NSManaged var isFavorite: Bool
    @NSManaged var sourceApp: String?   // localized name of the app the clip was copied from

    static func fetch() -> NSFetchRequest<Clip> { NSFetchRequest<Clip>(entityName: "Clip") }
}

/// Immutable value snapshot for the UI and debug bridge — decoupled from the
/// managed-object context (important for the NSPanel-hosted palette) and built
/// from a lightweight projection fetch so blob columns are never faulted in.
struct ClipItem: Identifiable, Equatable {
    let id: UUID
    let text: String
    let kind: ClipKind
    let createdAt: Date
    let isFavorite: Bool
    var sourceApp: String? = nil
}
