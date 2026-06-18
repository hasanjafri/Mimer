import CoreData
import Combine

/// The clipboard history, backed by Core Data. Publishes value-type `ClipItem`
/// snapshots for the UI. Dedupes by text (re-copy moves to top), prunes the
/// rolling history to the user's `historyLimit` (favorites never pruned), and
/// pins favorites to the top.
@MainActor
final class ClipStore: ObservableObject {
    static let shared = ClipStore()

    @Published private(set) var items: [ClipItem] = []

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
        let request = Clip.fetch()
        request.predicate = NSPredicate(format: "text == %@", text)
        request.fetchLimit = 1

        if let existing = (try? context.fetch(request))?.first {
            existing.createdAt = now      // re-copy → move to top
            existing.lastUsedAt = now
        } else {
            let clip = NSEntityDescription.insertNewObject(forEntityName: "Clip", into: context) as! Clip
            clip.id = UUID()
            clip.text = text
            clip.createdAt = now
            clip.lastUsedAt = now
            clip.isFavorite = false
        }
        prune()
        saveAndRefresh()
    }

    func toggleFavorite(_ id: UUID) {
        guard let clip = clip(with: id) else { return }
        clip.isFavorite.toggle()
        saveAndRefresh()
    }

    func setFavorite(_ id: UUID, _ isFavorite: Bool) {
        guard let clip = clip(with: id) else { return }
        clip.isFavorite = isFavorite
        saveAndRefresh()
    }

    func delete(_ id: UUID) {
        guard let clip = clip(with: id) else { return }
        context.delete(clip)
        saveAndRefresh()
    }

    private func clip(with id: UUID) -> Clip? {
        let request = Clip.fetch()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    private func prune() {
        let limit = historyLimitOverride ?? Preferences.shared.historyLimit
        let request = Clip.fetch()
        request.predicate = NSPredicate(format: "isFavorite == NO")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        guard let nonFavorites = try? context.fetch(request), nonFavorites.count > limit else { return }
        nonFavorites[limit...].forEach(context.delete)
    }

    private func saveAndRefresh() {
        if context.hasChanges { try? context.save() }
        refresh()
    }

    func refresh() {
        let request = Clip.fetch()
        // Favorites pinned to the top; then most-recent first.
        request.sortDescriptors = [
            NSSortDescriptor(key: "isFavorite", ascending: false),
            NSSortDescriptor(key: "createdAt", ascending: false)
        ]
        let clips = (try? context.fetch(request)) ?? []
        items = clips.compactMap { clip in
            guard let id = clip.id, let text = clip.text, let createdAt = clip.createdAt else { return nil }
            return ClipItem(id: id, text: text, createdAt: createdAt, isFavorite: clip.isFavorite)
        }
    }
}
