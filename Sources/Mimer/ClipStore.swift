import CoreData
import Combine
import CryptoKit

/// The clipboard history, backed by Core Data. Publishes value-type `ClipItem`
/// snapshots built from a lightweight *projection* fetch (never faults whole
/// managed objects / blob columns into the list path). Dedupes by `contentHash`
/// (kind-agnostic), prunes via a batched object-ID delete (favorites exempt),
/// and pins favorites to the top.
@MainActor
final class ClipStore: ObservableObject {
    static let shared = ClipStore()

    @Published private(set) var items: [ClipItem] = []

    /// Increments on every captured clip — drives the menu-bar "captured" pulse.
    @Published private(set) var captureTick: Int = 0

    /// Authored, kept-forever snippets (kind == .snippet), separate from history.
    @Published private(set) var snippets: [ClipItem] = []

    /// Test hook to override the history cap without touching global Preferences.
    var historyLimitOverride: Int?

    private let persistence: PersistenceController
    private var context: NSManagedObjectContext { persistence.viewContext }

    init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
    }

    func loadInitial() { refresh() }

    func insert(text: String) {
        let now = Date()
        let hash = Self.contentHash(text)

        let request = Clip.fetch()
        request.predicate = NSPredicate(format: "contentHash == %@ AND kind != %d", hash, ClipKind.snippet.rawValue)
        request.fetchLimit = 1

        if let existing = (try? context.fetch(request))?.first {
            existing.createdAt = now      // re-copy → move to top
            existing.lastUsedAt = now
        } else {
            let clip = NSEntityDescription.insertNewObject(forEntityName: "Clip", into: context) as! Clip
            clip.id = UUID()
            clip.text = text
            clip.contentHash = hash
            clip.kind = ClipKind.detect(from: text).rawValue
            clip.createdAt = now
            clip.lastUsedAt = now
            clip.isFavorite = false
        }

        save()        // persist before pruning (batch delete operates on the store)
        prune()
        refresh()
        captureTick &+= 1   // pulse the menu-bar icon
    }

    func toggleFavorite(_ id: UUID) {
        guard let clip = clip(with: id) else { return }
        clip.isFavorite.toggle()
        save(); refresh()
    }

    func setFavorite(_ id: UUID, _ isFavorite: Bool) {
        guard let clip = clip(with: id) else { return }
        clip.isFavorite = isFavorite
        save(); refresh()
    }

    func delete(_ id: UUID) {
        guard let clip = clip(with: id) else { return }
        context.delete(clip)
        save(); refresh()
    }

    /// Save an authored snippet (kept forever, exempt from pruning). Identical
    /// snippets are ignored; snippets never collide with captured history (the
    /// history dedupe is scoped to non-snippet kinds).
    func addSnippet(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let hash = Self.contentHash(trimmed)

        let existing = Clip.fetch()
        existing.predicate = NSPredicate(format: "contentHash == %@ AND kind == %d", hash, ClipKind.snippet.rawValue)
        existing.fetchLimit = 1
        if (try? context.fetch(existing))?.first != nil { refresh(); return }

        let clip = NSEntityDescription.insertNewObject(forEntityName: "Clip", into: context) as! Clip
        clip.id = UUID()
        clip.text = trimmed
        clip.contentHash = hash
        clip.kind = ClipKind.snippet.rawValue
        clip.createdAt = Date()
        clip.lastUsedAt = Date()
        clip.isFavorite = false
        save(); refresh()
    }

    // MARK: - Internals

    private func clip(with id: UUID) -> Clip? {
        let request = Clip.fetch()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    /// Prune the rolling history to the cap, favorites exempt. Fetches only object
    /// IDs (no full-object faulting), then batch-deletes the overflow and merges
    /// the deletions back into the view context.
    private func prune() {
        let limit = max(0, historyLimitOverride ?? Preferences.shared.historyLimit)

        let idRequest = NSFetchRequest<NSManagedObjectID>(entityName: "Clip")
        idRequest.resultType = .managedObjectIDResultType
        idRequest.includesPendingChanges = false
        idRequest.predicate = NSPredicate(format: "isFavorite == NO AND kind != %d", ClipKind.snippet.rawValue)
        idRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        guard let ids = try? context.fetch(idRequest), ids.count > limit else { return }
        let overflow = Array(ids[limit...])

        let batch = NSBatchDeleteRequest(objectIDs: overflow)
        batch.resultType = .resultTypeObjectIDs
        if let result = try? context.execute(batch) as? NSBatchDeleteResult,
           let deleted = result.result as? [NSManagedObjectID], !deleted.isEmpty {
            NSManagedObjectContext.mergeChanges(
                fromRemoteContextSave: [NSDeletedObjectsKey: deleted],
                into: [context]
            )
        }
    }

    private func save() {
        if context.hasChanges { try? context.save() }
    }

    /// Projection fetch: pull only the scalar fields the list needs, as a
    /// dictionary, so blob columns (added later) are never faulted into the UI path.
    func refresh() {
        let snippetKind = ClipKind.snippet.rawValue
        items = fetchProjection(
            predicate: NSPredicate(format: "kind != %d", snippetKind),
            sort: [NSSortDescriptor(key: "isFavorite", ascending: false),   // favorites pinned on top
                   NSSortDescriptor(key: "createdAt", ascending: false)]
        )
        snippets = fetchProjection(
            predicate: NSPredicate(format: "kind == %d", snippetKind),
            sort: [NSSortDescriptor(key: "createdAt", ascending: false)]
        )
    }

    /// Projection fetch: pull only the scalar fields the list needs, as a
    /// dictionary, so blob columns (added later) are never faulted into the UI path.
    private func fetchProjection(predicate: NSPredicate, sort: [NSSortDescriptor]) -> [ClipItem] {
        let request = NSFetchRequest<NSDictionary>(entityName: "Clip")
        request.resultType = .dictionaryResultType
        request.includesPendingChanges = false
        request.predicate = predicate
        request.propertiesToFetch = ["id", "text", "kind", "createdAt", "isFavorite"]
        request.sortDescriptors = sort
        let rows = (try? context.fetch(request)) ?? []
        return rows.compactMap { row in
            guard let id = row["id"] as? UUID,
                  let text = row["text"] as? String,
                  let createdAt = row["createdAt"] as? Date else { return nil }
            let kindRaw = (row["kind"] as? NSNumber)?.int16Value ?? 0
            let isFavorite = (row["isFavorite"] as? NSNumber)?.boolValue ?? false
            return ClipItem(
                id: id,
                text: text,
                kind: ClipKind(rawValue: kindRaw) ?? .text,
                createdAt: createdAt,
                isFavorite: isFavorite
            )
        }
    }

    private static func contentHash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
