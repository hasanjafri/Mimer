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
