import CoreData
import Combine

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
    private let cryptor: Cryptor
    private let blobStore: BlobStore
    private var context: NSManagedObjectContext { persistence.viewContext }

    init(persistence: PersistenceController = .shared, cryptor: Cryptor = .shared, blobStore: BlobStore = BlobStore()) {
        self.persistence = persistence
        self.cryptor = cryptor
        self.blobStore = blobStore
    }

    func loadInitial() {
        // With an ephemeral key (Keychain unusable) the key won't survive a restart, so we run
        // non-destructively: never migrate legacy plaintext into ciphertext we can't read back
        // (that would scrub still-recoverable data), and never vacuum (the pending marker stays
        // set for a future durable launch to finish the job). New clips still persist, but they
        // simply won't decrypt next launch — graceful loss, never corruption of existing data.
        if cryptor.isDurable {
            migrateToEncryptedIfNeeded()
            // Vacuum if a migration just ran OR a prior launch encrypted rows but crashed
            // before scrubbing (the pending marker survives that). Clear the marker only on a
            // confirmed scrub — otherwise leave it set so a failed vacuum retries next launch.
            if persistence.vacuumPending, persistence.vacuum() {
                persistence.clearVacuumPending()
            }
        }
        refresh()
    }

    func insert(text: String, sourceApp: String? = nil) {
        let now = Date()
        let hash = cryptor.dedupeHash(text)

        let request = Clip.fetch()
        request.predicate = NSPredicate(format: "contentHash == %@ AND kind != %d", hash, ClipKind.snippet.rawValue)
        request.fetchLimit = 1

        if let existing = (try? context.fetch(request))?.first {
            existing.createdAt = now      // re-copy → move to top
            existing.lastUsedAt = now
            existing.sourceApp = sourceApp.flatMap(cryptor.encrypt)   // refresh provenance (encrypted)
        } else {
            guard let encrypted = cryptor.encrypt(text) else { return }   // fail closed — never store plaintext
            let clip = NSEntityDescription.insertNewObject(forEntityName: "Clip", into: context) as! Clip
            clip.id = UUID()
            clip.text = encrypted
            clip.contentHash = hash
            clip.kind = ClipKind.detect(from: text).rawValue
            clip.createdAt = now
            clip.lastUsedAt = now
            clip.isFavorite = false
            clip.sourceApp = sourceApp.flatMap(cryptor.encrypt)   // metadata is encrypted too (keeps "ciphertext only")
        }

        // Only prune + pulse if the capture actually persisted — never batch-delete history
        // on the back of a failed (rolled-back) save.
        if save() {
            prune()             // persist before pruning (batch delete operates on the store)
            captureTick &+= 1   // pulse the menu-bar icon
        }
        refresh()
    }

    /// Capture an image clip: write the (encrypted, content-addressed) bytes to the blob store,
    /// then a row referencing them. Dedupes by the blob's keyed hash — re-copying the same image
    /// just moves the existing row to the top (no new blob, no new row).
    func insertImage(data: Data, sourceApp: String? = nil) {
        let hash = blobStore.hash(for: data)                 // the blob store owns the key (filename)
        let blobExistedBefore = blobStore.exists(hash)
        guard blobStore.store(data) == hash else { return }  // fail closed; persist exactly what's stored
        let now = Date()

        let request = Clip.fetch()
        request.predicate = NSPredicate(format: "blobHash == %@", hash)
        request.fetchLimit = 1
        if let existing = (try? context.fetch(request))?.first {
            existing.createdAt = now
            existing.lastUsedAt = now
            existing.sourceApp = sourceApp.flatMap(cryptor.encrypt)
        } else {
            guard let caption = cryptor.encrypt("Image") else {   // fail closed; don't persist an invisible row
                if !blobExistedBefore { blobStore.delete(hash) }
                return
            }
            let clip = NSEntityDescription.insertNewObject(forEntityName: "Clip", into: context) as! Clip
            clip.id = UUID()
            clip.text = caption          // a searchable/display caption; the bytes live in the blob
            clip.contentHash = hash       // dedupe key (== blobHash)
            clip.blobHash = hash
            clip.kind = ClipKind.image.rawValue
            clip.createdAt = now
            clip.lastUsedAt = now
            clip.isFavorite = false
            clip.sourceApp = sourceApp.flatMap(cryptor.encrypt)
        }

        if save() {
            prune()
            captureTick &+= 1
        } else if !blobExistedBefore {
            blobStore.delete(hash)   // row didn't persist → don't leave an orphaned blob we just wrote
        }
        refresh()
    }

    /// Decrypted bytes for an image clip's blob (nil if missing/corrupt). Used by the UI to
    /// render thumbnails and by paste-back to put the image on the pasteboard.
    func blobData(_ hash: String) -> Data? { blobStore.load(hash) }

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
        let blob = clip.blobHash
        context.delete(clip)
        guard save() else { refresh(); return }   // never touch blobs on a failed/rolled-back delete
        if let blob, !isBlobReferenced(blob) { blobStore.delete(blob) }   // only when no row still uses it
        refresh()
    }

    /// True if any row still references this blob (so we don't delete a shared/still-used file).
    private func isBlobReferenced(_ hash: String) -> Bool {
        let r = Clip.fetch()
        r.predicate = NSPredicate(format: "blobHash == %@", hash)
        r.fetchLimit = 1
        return ((try? context.count(for: r)) ?? 0) > 0
    }

    /// Wipe the rolling history. Favorites and snippets are kept (they're explicitly saved).
    func clearHistory() {
        let predicate = NSPredicate(format: "isFavorite == NO AND kind != %d", ClipKind.snippet.rawValue)
        let request = NSFetchRequest<NSManagedObjectID>(entityName: "Clip")
        request.resultType = .managedObjectIDResultType
        request.predicate = predicate
        guard let ids = try? context.fetch(request), !ids.isEmpty else { return }
        batchDelete(ids)
        refresh()
    }

    /// Batch-delete the given rows, then delete the blob files of *exactly the rows the store
    /// confirmed deleted* — and only for blobs no surviving row still references.
    private func batchDelete(_ ids: [NSManagedObjectID]) {
        let hashByID = blobHashesByID(ids)   // (objectID → blobHash) captured before the rows vanish
        let batch = NSBatchDeleteRequest(objectIDs: ids)
        batch.resultType = .resultTypeObjectIDs
        guard let result = try? context.execute(batch) as? NSBatchDeleteResult,
              let deleted = result.result as? [NSManagedObjectID], !deleted.isEmpty else { return }
        NSManagedObjectContext.mergeChanges(fromRemoteContextSave: [NSDeletedObjectsKey: deleted], into: [context])
        // Only clean blobs whose row was actually deleted (not merely requested).
        let confirmed = Set(deleted)
        let blobs = Set(hashByID.compactMap { confirmed.contains($0.key) ? $0.value : nil })
        for blob in blobs where !isBlobReferenced(blob) { blobStore.delete(blob) }
    }

    /// Map of objectID → non-nil blobHash for *exactly* the given rows, so blob deletion can be
    /// keyed to the rows the store confirms it deleted (not a predicate/offset replay that shifts).
    private func blobHashesByID(_ ids: [NSManagedObjectID]) -> [NSManagedObjectID: String] {
        guard !ids.isEmpty else { return [:] }
        let r = Clip.fetch()
        r.predicate = NSPredicate(format: "self IN %@", ids)
        var map: [NSManagedObjectID: String] = [:]
        for clip in (try? context.fetch(r)) ?? [] where clip.blobHash != nil {
            map[clip.objectID] = clip.blobHash
        }
        return map
    }

    /// Save an authored snippet (kept forever, exempt from pruning). Identical
    /// snippets are ignored; snippets never collide with captured history (the
    /// history dedupe is scoped to non-snippet kinds).
    func addSnippet(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let hash = cryptor.dedupeHash(trimmed)

        let existing = Clip.fetch()
        existing.predicate = NSPredicate(format: "contentHash == %@ AND kind == %d", hash, ClipKind.snippet.rawValue)
        existing.fetchLimit = 1
        if (try? context.fetch(existing))?.first != nil { refresh(); return }

        guard let encrypted = cryptor.encrypt(trimmed) else { return }   // fail closed
        let clip = NSEntityDescription.insertNewObject(forEntityName: "Clip", into: context) as! Clip
        clip.id = UUID()
        clip.text = encrypted
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
        batchDelete(Array(ids[limit...]))   // delete the overflow rows + their blob files
    }

    @discardableResult
    private func save() -> Bool {
        guard context.hasChanges else { return true }
        do {
            try context.save()
            return true
        } catch {
            NSLog("Mimer ClipStore save failed: \(error.localizedDescription)")
            context.rollback()   // discard the failed change so the context stays consistent
            return false
        }
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
        request.propertiesToFetch = ["id", "text", "kind", "createdAt", "isFavorite", "sourceApp", "blobHash"]
        request.sortDescriptors = sort
        let rows = (try? context.fetch(request)) ?? []
        return rows.compactMap { row in
            guard let id = row["id"] as? UUID,
                  let stored = row["text"] as? String,
                  let createdAt = row["createdAt"] as? Date else { return nil }
            // Surface (don't silently drop) a row we can't decrypt — the key changed or
            // the value is corrupt. A visible placeholder signals lost history instead of
            // making it vanish; the real value can't be recovered without the key.
            let text = cryptor.decrypt(stored) ?? "⚠️ Unreadable clip — encryption key unavailable"
            let kindRaw = (row["kind"] as? NSNumber)?.int16Value ?? 0
            let isFavorite = (row["isFavorite"] as? NSNumber)?.boolValue ?? false
            return ClipItem(
                id: id,
                text: text,
                kind: ClipKind(rawValue: kindRaw) ?? .text,
                createdAt: createdAt,
                isFavorite: isFavorite,
                sourceApp: (row["sourceApp"] as? String).flatMap(cryptor.decrypt),
                blobHash: row["blobHash"] as? String
            )
        }
    }

    /// One-time, idempotent encrypt of any legacy plaintext rows (from before
    /// encrypt-at-rest). The predicate matches only un-prefixed rows, so once the
    /// store is fully encrypted this fetches nothing — no flag needed, and the
    /// projection's no-blob-faulting guarantee is preserved on every later launch.
    /// Re-encrypting recomputes `contentHash` as the keyed HMAC from the plaintext.
    /// Idempotent (the predicate matches only un-prefixed rows). Marks a vacuum pending
    /// *before* saving so a crash after the save still triggers the scrub next launch;
    /// only encrypts rows that seal successfully, and only commits via a verified save.
    private func migrateToEncryptedIfNeeded() {
        let request = Clip.fetch()
        request.predicate = NSPredicate(format: "text != nil AND NOT (text BEGINSWITH %@)", Cryptor.prefix)
        guard let legacy = try? context.fetch(request), !legacy.isEmpty else { return }

        var rewrote = false
        for clip in legacy {
            guard let plaintext = clip.text, let encrypted = cryptor.encrypt(plaintext) else { continue }
            clip.text = encrypted
            clip.contentHash = cryptor.dedupeHash(plaintext)
            rewrote = true
        }
        guard rewrote else { return }
        // Persist the scrub marker (durably) BEFORE committing the encrypting save. If the
        // marker can't be written, roll back rather than commit ciphertext with no record
        // that the freed plaintext still needs scrubbing — we'll retry the whole migration
        // next launch. The marker is never cleared here (only a confirmed vacuum clears it),
        // so a save failure or a prior launch's unscrubbed debt is preserved.
        guard persistence.setVacuumPending() else {
            NSLog("Mimer: deferring encryption migration — vacuum marker not persistable")
            context.rollback()
            return
        }
        save()
    }
}
