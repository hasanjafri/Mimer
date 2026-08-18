#if DEBUG
import AppKit
import Foundation
import SwiftUI

/// DEBUG-only test bridge so an automated agent (or you) can drive and inspect
/// Mimer without GUI automation: it writes live state to `_debug_state.json` and
/// executes commands written to `_debug_cmd`. Never compiled into release builds.
///
/// Commands (write one to _debug_cmd): `open`, `close`, `paste <i>`, `settings`,
/// `fav <i>`, `delete <i>`, `pause`, `resume`, `snapshot`, `peek <i>` (hover card for a clip),
/// `requestpaste` (prompt for PostEvent).
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
            MainActor.assumeIsolated { self?.tick() }   // scheduled on the main runloop
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
        case "stack":   // e.g. "stack 0 2 4" — open the palette with those clips pre-stacked
            let idxs = (parts.count > 1 ? parts[1] : "").split(separator: " ").compactMap { Int($0) }
            PaletteController.shared.open(stackIndices: idxs.isEmpty ? nil : idxs)
        case "snippet":
            if parts.count > 1 { ClipStore.shared.addSnippet(parts[1]) }
        case "composer": SnippetComposerWindowController.shared.show()
        case "peek":
            // Show the hover card for a clip — beside the palette if it's open, otherwise
            // anchored to the screen. The mouse-driven path isn't reachable headlessly.
            if parts.count > 1, let index = Int(parts[1]) {
                let items = ClipStore.shared.snippets + ClipStore.shared.items
                if items.indices.contains(index) {
                    let item = items[index]
                    ClipPeek.shared.debugPeek(item,
                                              action: ClipAction.of(item.text, config: Preferences.shared.devConfig))
                }
            }
        case "requestpaste": _ = Paster.requestPostEventAccess()   // trigger the macOS PostEvent prompt (E2E harness)
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
        // Hover cards: the newest real clip, plus a synthetic long one so the middle-elision
        // treatment is always in the snapshot set even when the history has no long clips.
        if let first = menuItems.first {
            write(renderPNG(ClipInspectorCard(inspector: ClipInspector.make(for: first,
                                                                           maskSecrets: Preferences.shared.maskSecrets,
                                                                           action: ClipAction.of(first.text, config: Preferences.shared.devConfig))),
                            width: ClipInspectorCard.width), "render-peek.png")
        }
        write(renderPNG(ClipInspectorCard(inspector: ClipInspector.make(for: Self.longSampleClip,
                                                                       maskSecrets: true,
                                                                       query: "shipping")),
                        width: ClipInspectorCard.width), "render-peek-long.png")
        // One sheet of every content treatment, for design review of the card.
        write(renderPNG(
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(Self.formatSampleClips.enumerated()), id: \.offset) { _, sample in
                    ClipInspectorCard(inspector: ClipInspector.make(for: sample,
                                                                    maskSecrets: true,
                                                                    action: ClipAction.of(sample.text)))
                }
            }.padding(12),
            width: CGFloat(Self.formatSampleClips.count) * (ClipInspectorCard.width + 12) + 12
        ), "render-peek-formats.png")
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

    /// A long, multi-line clip for the snapshot harness: exercises middle elision, the line
    /// counts, and search highlighting in one render.
    private static let longSampleClip = ClipItem(
        id: UUID(),
        text: (1...40).map { "\($0). shipping notes — the middle of a long clip is exactly what a truncated row hides" }
            .joined(separator: "\n"),
        kind: .text,
        createdAt: Date().addingTimeInterval(-3600),
        isFavorite: true,
        sourceApp: "Xcode"
    )

    /// One clip per content treatment (JSON · diff · code · tracked URL · secret) so the
    /// snapshot sheet always shows every path the card can take.
    private static let formatSampleClips: [ClipItem] = [
        sample(#"{"id":42,"name":"Ada Lovelace","roles":["admin","owner"],"active":true,"meta":{"seen":null,"score":9.75}}"#,
               app: "Terminal"),
        sample("""
            diff --git a/Sources/Mimer/ClipPeek.swift b/Sources/Mimer/ClipPeek.swift
            index 1111111..2222222 100644
            --- a/Sources/Mimer/ClipPeek.swift
            +++ b/Sources/Mimer/ClipPeek.swift
            @@ -42,7 +42,9 @@ final class ClipPeek {
                 func hover(_ item: ClipItem) {
            -        show(item, delay: 0.2)
            -        watchdog.start()
            +        show(item, delay: Self.hoverDelay)
            +        // the pointer owns this card now
            +        watchdog.start(anchoredToPointer: true)
                 }

            @@ -84,10 +86,14 @@ final class ClipPeek {
                 private func present() {
            -        guard let pending else { return }
            +        guard let pending, Preferences.shared.maskSecrets == maskedWhenShown else { return }
                     let panel = self.panel ?? ClipPeekPanel()
            -        panel.contentView = NSHostingView(rootView: pending.card)
            +        let hosting = NSHostingView(rootView: pending.card)
            +        panel.contentView = hosting
            +        hosting.layoutSubtreeIfNeeded()
                     panel.orderFrontRegardless()
                 }

            @@ -120,6 +126,9 @@ final class ClipPeek {
                 private func checkStillValid() {
            -        guard let host, host.isVisible else { hide(); return }
            +        guard let host else { return pointerDrifted() ? hide() : () }
            +        guard host.isVisible else { hide(reason: "host-gone"); return }
            +        if anchoredToPointer, !host.frame.contains(NSEvent.mouseLocation) { hide() }
                 }
            """, app: "Xcode"),
        sample("""
            // keep the newest capture on top
            func insert(text: String) -> Bool {
                guard !text.isEmpty else { return false }
                let hash = cryptor.dedupeHash(text)   /* keyed, never raw */
                SELECT id FROM clips WHERE content_hash = hash LIMIT 1
                return store.save(text, hash: hash, limit: 200)
            }
            """, kind: .code, app: "Cursor"),
        sample("https://mimer.hasanjafri.com/compare?utm_source=newsletter&utm_campaign=launch&plan=pro&fbclid=IwAR2x9",
               kind: .link, app: "Safari"),
        sample("AKIAIOSFODNN7EXAMPLE", app: "1Password"),
        // Past the counting limit: the card reports size, not counts it never read.
        sample(String(repeating: "2026-08-18 14:02:11 INFO  request served in 12ms  path=/api/clips\n",
                      count: 20_000), app: "Console")
    ]

    private static func sample(_ text: String, kind: ClipKind = .text, app: String) -> ClipItem {
        ClipItem(id: UUID(), text: text, kind: kind, createdAt: Date().addingTimeInterval(-900),
                 isFavorite: false, sourceApp: app)
    }

    private func writeState() {
        // Never write a raw secret to the debug state file (it's plaintext on disk).
        let redact: (String) -> String = { SecretDetector.maskedPreview($0) ?? $0 }
        let state: [String: Any] = [
            "paletteVisible": PaletteController.shared.isPaletteVisible,
            "paletteKey": PaletteController.shared.isPaletteKey,
            "firstResponder": PaletteController.shared.firstResponderDescription,
            "canPostEvents": Paster.canPostEvents,
            "settingsVisible": SettingsWindowController.shared.isVisible,
            "isPaused": Preferences.shared.isPaused,
            "paletteFrame": PaletteController.shared.panelWindow.map {
                ["x": $0.frame.minX, "y": $0.frame.minY, "w": $0.frame.width, "h": $0.frame.height]
            } ?? [:],
            "windows": NSApp.windows.filter(\.isVisible).map {
                ["class": String(describing: type(of: $0)), "level": $0.level.rawValue,
                 "x": $0.frame.minX, "y": $0.frame.minY, "w": $0.frame.width, "h": $0.frame.height]
            },
            "peekVisible": ClipPeek.shared.isVisible,
            "peekLog": ClipPeek.shared.eventLog,
            "clipCount": ClipStore.shared.items.count,
            "clips": Array(ClipStore.shared.items.prefix(10).map { redact($0.text) }),
            "favorites": ClipStore.shared.items.filter(\.isFavorite).map { redact($0.text) }
        ]
        if let data = try? JSONSerialization.data(
            withJSONObject: state, options: [.prettyPrinted, .sortedKeys]
        ) {
            try? data.write(to: stateURL)
        }
    }
}
#endif
