import AppKit
import SwiftUI

/// Hosts the first-run `OnboardingView` in an owned AppKit window (same reason as
/// `SettingsWindowController` — SwiftUI windows are unreliable for LSUIElement agents).
@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private var window: NSWindow?

    func showIfNeeded() {
        guard !Preferences.shared.hasOnboarded else { return }
        show()
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 440),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = "Welcome to Mimer"
            w.isReleasedWhenClosed = false
            w.center()
            w.contentView = NSHostingView(rootView: OnboardingView(onDone: { [weak self] in
                Preferences.shared.hasOnboarded = true
                self?.window?.close()
            }))
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
