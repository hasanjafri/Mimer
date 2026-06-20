import AppKit
import SwiftUI

/// Hosts the snippet composer in an owned AppKit window (same reason as the other
/// controllers — SwiftUI windows are unreliable for LSUIElement agents). Recreated
/// each show so the editor starts empty.
@MainActor
final class SnippetComposerWindowController {
    static let shared = SnippetComposerWindowController()

    private var window: NSWindow?

    func show() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "New Snippet"
        w.isReleasedWhenClosed = false
        w.center()
        w.contentView = NSHostingView(rootView: SnippetComposerView(
            onSave: { [weak self] text in
                ClipStore.shared.addSnippet(text)
                self?.dismiss()
            },
            onCancel: { [weak self] in self?.dismiss() }
        ))
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    private func dismiss() {
        window?.close()
        window = nil
    }
}
