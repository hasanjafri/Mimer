#if DEBUG
import AppKit
import Foundation
import SwiftUI

/// DEBUG-only test bridge so an automated agent (or you) can drive and inspect
/// Mimer without GUI automation: it writes live state to `_debug_state.json` and
/// executes commands written to `_debug_cmd`. Never compiled into release builds.
///
/// Commands (write one to _debug_cmd): `open`, `close`, `paste <i>`, `settings`,
/// `fav <i>`, `delete <i>`, `pause`, `resume`, `snapshot`.
/// `snapshot` renders Mimer's own windows to PNGs in `_snapshots/` (no Screen
/// Recording permission needed — the app draws itself). Inject clips for capture
/// testing from the shell with `pbcopy` (no bridge needed).
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
        case "pause": Preferences.shared.isPaused = true
        case "resume": Preferences.shared.isPaused = false
        case "snapshot": writeSnapshots()
        case "transform":
            if parts.count > 1, let index = Int(parts[1]) {
                PaletteController.shared.open(transformIndex: index)
            }
        case "snippet":
            if parts.count > 1 { ClipStore.shared.addSnippet(parts[1]) }
        case "composer": SnippetComposerWindowController.shared.show()
        default: break
        }
    }

    /// DEBUG visual feedback: render Mimer's own surfaces to PNGs the agent can read.
    /// Uses the app drawing itself (ImageRenderer / cacheDisplay), NOT screen capture —
    /// so it needs no Screen Recording permission.
    private func writeSnapshots() {
        let snapDir = dir.appendingPathComponent("_snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: snapDir, withIntermediateDirectories: true)
        for f in (try? FileManager.default.contentsOfDirectory(at: snapDir, includingPropertiesForKeys: nil)) ?? [] {
            try? FileManager.default.removeItem(at: f)
        }

        func write(_ data: Data?, _ name: String) {
            if let data { try? data.write(to: snapDir.appendingPathComponent(name)) }
        }
        func renderPNG<V: View>(_ view: V, width: CGFloat) -> Data? {
            let renderer = ImageRenderer(content: view.frame(width: width))
            renderer.scale = 2
            guard let img = renderer.nsImage,
                  let tiff = img.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else { return nil }
            return rep.representation(using: .png, properties: [:])
        }
        func livePNG(_ view: NSView) -> Data? {
            guard view.bounds.width > 1, view.bounds.height > 1,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
            view.cacheDisplay(in: view.bounds, to: rep)
            return rep.representation(using: .png, properties: [:])
        }

        // Deterministic standalone renders (always available, permission-free).
        write(renderPNG(MenuBarView(), width: 320), "render-menu.png")
        // Copy-feedback states (hover + "Copied" badge) — transient at runtime, so
        // seed them explicitly here for the self-test loop to inspect.
        let menuItems = ClipStore.shared.items
        write(renderPNG(
            MenuBarView(debugCopiedID: menuItems.first?.id,
                        debugHoverID: menuItems.count > 1 ? menuItems[1].id : nil),
            width: 320), "render-menu-feedback.png")
        write(renderPNG(PaletteView(onPaste: { _ in }, onClose: {}), width: 640), "render-palette.png")
        write(renderPNG(OnboardingView(onDone: {}), width: 440), "render-onboarding.png")

        // Plus whatever live windows are on screen (real material/vibrancy).
        var i = 0
        for window in NSApp.windows where window.isVisible {
            guard let v = window.contentView, let data = livePNG(v) else { continue }
            let title = window.title.isEmpty ? "panel" : window.title.replacingOccurrences(of: " ", with: "_")
            write(data, "live-\(i)-\(title).png")
            i += 1
        }
        NSLog("Mimer snapshot → \(snapDir.path)")
    }

    private func writeState() {
        let state: [String: Any] = [
            "paletteVisible": PaletteController.shared.isPaletteVisible,
            "paletteKey": PaletteController.shared.isPaletteKey,
            "firstResponder": PaletteController.shared.firstResponderDescription,
            "canPostEvents": Paster.canPostEvents,
            "settingsVisible": SettingsWindowController.shared.isVisible,
            "isPaused": Preferences.shared.isPaused,
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
