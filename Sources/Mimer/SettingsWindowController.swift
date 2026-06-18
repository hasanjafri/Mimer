import AppKit
import SwiftUI

/// Hosts the SwiftUI `SettingsView` in a dedicated AppKit window. The SwiftUI
/// `Settings` scene / `SettingsLink` is unreliable for `LSUIElement` agent apps
/// (no regular activation), so we own the window and bring the app forward
/// ourselves. Agent apps stay Dock-icon-less even when activated.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "Mimer Settings"
            w.contentView = NSHostingView(rootView: SettingsView())
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
