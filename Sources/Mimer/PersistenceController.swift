import CoreData

/// Core Data stack with a programmatic (code-first) model — no `.xcdatamodeld`
/// bundle, so the schema lives in diffable Swift. The model is CloudKit-valid
/// (optional/defaulted attributes, no unique constraints, no ordered relationships)
/// so enabling `NSPersistentCloudKitContainer` later is a container swap, not a
/// schema migration.
final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer
    var viewContext: NSManagedObjectContext { container.viewContext }
    private let storeFileURL: URL?

    /// Crash-safe "an encryption migration rewrote rows; their freed plaintext still
    /// needs scrubbing" marker. Persisted (UserDefaults, keyed by store path so tests
    /// and the real store don't collide) so a crash between the migration save and the
    /// vacuum still triggers the scrub on the next launch. No-op for in-memory stores.
    var vacuumPending: Bool {
        get { storeFileURL.map { UserDefaults.standard.bool(forKey: Self.vacuumKey($0)) } ?? false }
        set { storeFileURL.map { UserDefaults.standard.set(newValue, forKey: Self.vacuumKey($0)) } }
    }
    private static func vacuumKey(_ url: URL) -> String { "MimerVacuumPending:" + url.path }

    init(inMemory: Bool = false, storeURL: URL? = nil) {
        container = NSPersistentContainer(name: "Mimer", managedObjectModel: PersistenceController.model)
        let description = container.persistentStoreDescriptions.first
        if let storeURL {
            description?.url = storeURL
        } else if inMemory {
            description?.url = URL(fileURLWithPath: "/dev/null")
        } else {
            let dir = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Mimer", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            description?.url = dir.appendingPathComponent("Mimer.sqlite")
        }
        // Additive attributes (kind, contentHash) migrate via inferred lightweight migration.
        description?.shouldMigrateStoreAutomatically = true
        description?.shouldInferMappingModelAutomatically = true
        // secure_delete zeros freed cells (so deletes/prunes and the one-time encryption
        // rewrite don't leave plaintext in free pages), not just mark them reusable.
        description?.setOption(["secure_delete": "ON"] as NSDictionary, forKey: NSSQLitePragmasOption)
        let resolved = description?.url
        storeFileURL = (resolved?.path == "/dev/null") ? nil : resolved
        container.loadPersistentStores { _, error in
            if let error { NSLog("Mimer Core Data load error: \(error.localizedDescription)") }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    /// Rebuild the sqlite file (VACUUM) and truncate the WAL. VACUUM rewrites the
    /// database from scratch, so free pages — which can still hold pre-encryption
    /// plaintext even after the rows were re-encrypted — are dropped. Called once,
    /// right after the encryption migration actually rewrites legacy rows.
    func vacuum() {
        let coordinator = container.persistentStoreCoordinator
        guard let store = coordinator.persistentStores.first,
              let url = store.url, url.path != "/dev/null" else { return }
        let originalOptions = store.options   // to restore the store if the vacuum re-add fails

        // Drop registered objects before swapping the store out from under the context.
        container.viewContext.reset()
        do {
            try coordinator.remove(store)
        } catch {
            NSLog("Mimer vacuum: store remove failed (\(error.localizedDescription)); store left intact")
            return
        }
        do {
            try coordinator.addPersistentStore(
                ofType: NSSQLiteStoreType, configurationName: nil, at: url,
                options: [NSSQLiteManualVacuumOption: true,
                          NSSQLitePragmasOption: ["secure_delete": "ON"],
                          NSMigratePersistentStoresAutomaticallyOption: true,
                          NSInferMappingModelAutomaticallyOption: true])
        } catch {
            // Never leave the coordinator store-less: re-add the original store so fetches work.
            NSLog("Mimer vacuum: re-add with VACUUM failed (\(error.localizedDescription)); restoring store")
            _ = try? coordinator.addPersistentStore(
                ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: originalOptions)
        }
    }

    /// Single shared model instance (reused across containers to avoid duplicate-entity warnings).
    static let model: NSManagedObjectModel = {
        let model = NSManagedObjectModel()

        let clip = NSEntityDescription()
        clip.name = "Clip"
        clip.managedObjectClassName = NSStringFromClass(Clip.self)

        func attribute(_ name: String, _ type: NSAttributeType, defaultValue: Any? = nil) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = true
            if let defaultValue { a.defaultValue = defaultValue }
            return a
        }

        clip.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("text", .stringAttributeType),
            attribute("contentHash", .stringAttributeType),
            attribute("kind", .integer16AttributeType, defaultValue: 0),
            attribute("createdAt", .dateAttributeType),
            attribute("lastUsedAt", .dateAttributeType),
            attribute("isFavorite", .booleanAttributeType, defaultValue: false)
        ]
        model.entities = [clip]
        return model
    }()
}
