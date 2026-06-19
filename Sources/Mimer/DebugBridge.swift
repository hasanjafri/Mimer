#if DEBUG
import AppKit
import Foundation

/// DEBUG-only test bridge so an automated agent (or you) can drive and inspect
/// Mimer without GUI automation: it writes live state to `_debug_state.json` and
/// executes commands written to `_debug_cmd`. Never compiled into release builds.
///
/// Commands (write one to _debug_cmd): `open`, `close`, `paste <index>`.
/// Inject clips for capture testing from the shell with `pbcopy` (no bridge needed).
@MainActor
final class DebugBridge {
    static let shared = DebugBridge()

    private var timer: Timer?
    private let dir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Mimer", isDirectory: true)
    private var cmdURL: URL { dir.appendingPathComponent("_debug_cmd") }
    private var stateURL: URL { dir.appendingPathComponent("_debug_state.json") }

    func start() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? "".write(to: cmdURL, atomically: true, encoding: .utf8)
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.tick()
        }
        NSLog("Mimer DebugBridge active — cmd: \(cmdURL.path)")
    }

    private func tick() {
        if let raw = try? String(contentsOf: cmdURL, encoding: .utf8) {
            let cmd = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cmd.isEmpty {
                try? "".write(to: cmdURL, atomically: true, encoding: .utf8)
                handle(cmd)
            }
        }
        writeState()
    }

    private func handle(_ cmd: String) {
        let parts = cmd.split(separator: " ", maxSplits: 1).map(String.init)
        switch parts.first {
        case "open": PaletteController.shared.open()
        case "close": PaletteController.shared.close()
        case "paste":
            if parts.count > 1, let index = Int(parts[1]) {
                PaletteController.shared.pasteClip(at: index)
            }
        case "settings": SettingsWindowController.shared.show()
        case "fav":
            if parts.count > 1, let index = Int(parts[1]) {
                let items = ClipStore.shared.items
                if items.indices.contains(index) { ClipStore.shared.toggleFavorite(items[index].id) }
            }
        case "delete":
            if parts.count > 1, let index = Int(parts[1]) {
                let items = ClipStore.shared.items
                if items.indices.contains(index) { ClipStore.shared.delete(items[index].id) }
            }
        default: break
        }
    }

    private func writeState() {
        let state: [String: Any] = [
            "paletteVisible": PaletteController.shared.isPaletteVisible,
            "paletteKey": PaletteController.shared.isPaletteKey,
            "firstResponder": PaletteController.shared.firstResponderDescription,
            "canPostEvents": Paster.canPostEvents,
            "settingsVisible": SettingsWindowController.shared.isVisible,
            "clipCount": ClipStore.shared.items.count,
            "clips": Array(ClipStore.shared.items.prefix(10).map(\.text)),
            "favorites": ClipStore.shared.items.filter(\.isFavorite).map(\.text)
        ]
        if let data = try? JSONSerialization.data(
            withJSONObject: state, options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: stateURL)
        }
    }
}
#endif
