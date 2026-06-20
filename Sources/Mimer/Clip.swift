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
}

extension ClipKind {
    /// Best-effort classification for display (glyphs / treatment). Conservative:
    /// flags only high-confidence links, hex colors, and code — otherwise `.text`.
    static func detect(from raw: String) -> ClipKind {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .text }

        if !text.contains(where: \.isWhitespace) {
            let lower = text.lowercased()
            if lower.hasPrefix("http://") || lower.hasPrefix("https://")
                || lower.hasPrefix("www.") || lower.contains("://") {
                return .link
            }
        }
        if isHexColor(text) { return .color }
        if looksLikeCode(raw) { return .code }
        return .text
    }

    private static func isHexColor(_ s: String) -> Bool {
        guard s.hasPrefix("#") else { return false }   // require '#' so words like "facade" aren't colors
        let hex = s.dropFirst()
        return [3, 4, 6, 8].contains(hex.count) && hex.allSatisfy(\.isHexDigit)
    }

    private static func looksLikeCode(_ s: String) -> Bool {
        if s.contains("{") && s.contains("}") { return true }
        if s.contains("=>") || s.contains("</") || s.contains("/>") { return true }
        if s.contains(";\n") || s.hasSuffix(";") { return true }
        let starts = ["func ", "def ", "const ", "function ", "import ",
                      "#include", "package ", "<?xml", "<!DOCTYPE", "SELECT "]
        let head = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if starts.contains(where: { head.hasPrefix($0) }) { return true }
        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count >= 2, lines.contains(where: { $0.hasPrefix("  ") || $0.hasPrefix("\t") }) {
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
}
