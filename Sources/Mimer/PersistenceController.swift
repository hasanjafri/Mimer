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
    /// needs scrubbing" marker. Backed by a sidecar file next to the store (not
    /// UserDefaults, which buffers in memory and isn't ordered with the Core Data save).
    /// Setting it true writes + fsyncs the file, so once the migration save is durable the
    /// marker is too — a crash before the vacuum still triggers the scrub next launch.
    /// Per-store (keyed by path) so tests and the real store don't collide; no-op in-memory.
    private var vacuumMarkerURL: URL? { storeFileURL?.appendingPathExtension("vacuum-pending") }

    var vacuumPending: Bool {
        vacuumMarkerURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }

    /// Durably create the marker — fsync the file *and* its parent directory so the new
    /// entry survives a crash — and report success. The migration must only commit the
    /// encrypting save if this returns true; otherwise there'd be ciphertext on disk with
    /// no record that the freed plaintext still needs scrubbing. In-memory stores have
    /// nothing to persist (and vacuum is a no-op), so they return true.
    @discardableResult
    func setVacuumPending() -> Bool {
        guard let url = vacuumMarkerURL else { return true }
        let fd = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        guard fd >= 0 else { NSLog("Mimer: could not create vacuum marker at \(url.path)"); return false }
        let fileSynced = fsync(fd) == 0
        close(fd)
        guard fileSynced else { NSLog("Mimer: could not fsync vacuum marker"); return false }
        // The new directory entry must be durable too — fail if we can't confirm it.
        let dirFd = open(url.deletingLastPathComponent().path, O_RDONLY)
        guard dirFd >= 0 else { NSLog("Mimer: could not open store dir to fsync marker entry"); return false }
        let dirSynced = fsync(dirFd) == 0
        close(dirFd)
        guard dirSynced else { NSLog("Mimer: could not fsync store dir for marker entry"); return false }
        return true
    }

    func clearVacuumPending() {
        vacuumMarkerURL.map { try? FileManager.default.removeItem(at: $0) }
    }

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
    /// Returns true **only** if the VACUUM actually completed — so the caller clears the
    /// crash-safe scrub marker only on a confirmed scrub. On any failure the store is left
    /// (or put back) usable and we return false, leaving the marker set to retry next launch.
    @discardableResult
    func vacuum() -> Bool {
        let coordinator = container.persistentStoreCoordinator
        guard let store = coordinator.persistentStores.first,
              let url = store.url, url.path != "/dev/null" else { return false }
        let originalOptions = store.options   // to restore the store if the vacuum re-add fails

        // Drop registered objects before swapping the store out from under the context.
        container.viewContext.reset()
        do {
            try coordinator.remove(store)
        } catch {
            NSLog("Mimer vacuum: store remove failed (\(error.localizedDescription)); store left intact")
            return false
        }
        do {
            try coordinator.addPersistentStore(
                ofType: NSSQLiteStoreType, configurationName: nil, at: url,
                options: [NSSQLiteManualVacuumOption: true,
                          NSSQLitePragmasOption: ["secure_delete": "ON"],
                          NSMigratePersistentStoresAutomaticallyOption: true,
                          NSInferMappingModelAutomaticallyOption: true])
            return true
        } catch {
            // VACUUM re-add failed — put the original store back so the app isn't store-less.
            NSLog("Mimer vacuum: re-add with VACUUM failed (\(error.localizedDescription)); restoring store")
            do {
                try coordinator.addPersistentStore(
                    ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: originalOptions)
            } catch {
                NSLog("Mimer vacuum: CRITICAL — could not restore the store (\(error.localizedDescription)); persistence is offline until relaunch")
            }
            return false   // scrub did not happen → keep the marker, retry next launch
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
