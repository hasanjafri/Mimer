import CoreData

/// Persisted clipboard entry. CloudKit-valid: all attributes optional/defaulted.
/// Phase 1 is text-only; `kind`, image/file blobs, pinboards, and tags arrive later.
@objc(Clip)
final class Clip: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var text: String?
    @NSManaged var createdAt: Date?
    @NSManaged var lastUsedAt: Date?
    @NSManaged var isFavorite: Bool

    static func fetch() -> NSFetchRequest<Clip> { NSFetchRequest<Clip>(entityName: "Clip") }
}

/// Immutable value snapshot for the UI and debug bridge — decouples views from
/// the managed-object context (important for the NSPanel-hosted palette).
struct ClipItem: Identifiable, Equatable {
    let id: UUID
    let text: String
    let createdAt: Date
    let isFavorite: Bool
}
