import SwiftUI

@main
struct MimerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

/// Owns long-lived services — clipboard monitor, command-palette panel, global
/// hotkeys — wired up starting in Phase 1. Kept on the delegate (not a SwiftUI
/// view) so they outlive any view's lifecycle.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: ClipboardMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Agent app (LSUIElement): no Dock icon, menu-bar presence only.
        ClipStore.shared.loadInitial()
        let monitor = ClipboardMonitor(
            shouldCapture: { CaptureGate.captureAllowed() },
            onCapture: { text in
                // The frontmost app at capture time is (best-effort) where the clip came from.
                // Don't attribute to Mimer itself (ambiguous) → store nil.
                let app = NSWorkspace.shared.frontmostApplication
                let source = app?.bundleIdentifier == Bundle.main.bundleIdentifier ? nil : app?.localizedName
                ClipStore.shared.insert(text: text, sourceApp: source)
            }
        )
        monitor.start()
        self.monitor = monitor

        PaletteController.shared.setup()
        OnboardingWindowController.shared.showIfNeeded()
        _ = UpdaterController.shared   // start Sparkle's auto-update checks
        #if DEBUG
        DebugBridge.shared.start()
        #endif
    }
}
