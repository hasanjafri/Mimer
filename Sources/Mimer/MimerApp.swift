import SwiftUI

@main
struct MimerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Mimer", systemImage: "doc.on.clipboard") {
            MenuBarView()
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
        let monitor = ClipboardMonitor(onCapture: { text in
            ClipStore.shared.insert(text: text)
        })
        monitor.start()
        self.monitor = monitor

        PaletteController.shared.setup()
        OnboardingWindowController.shared.showIfNeeded()
        #if DEBUG
        DebugBridge.shared.start()
        #endif
    }
}
