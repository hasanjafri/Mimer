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
        do {
            try coordinator.remove(store)
            try coordinator.addPersistentStore(
                ofType: NSSQLiteStoreType, configurationName: nil, at: url,
                options: [NSSQLiteManualVacuumOption: true,
                          NSSQLitePragmasOption: ["secure_delete": "ON"],
                          NSMigratePersistentStoresAutomaticallyOption: true,
                          NSInferMappingModelAutomaticallyOption: true])
            container.viewContext.reset()
        } catch {
            NSLog("Mimer vacuum failed: \(error.localizedDescription)")
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
