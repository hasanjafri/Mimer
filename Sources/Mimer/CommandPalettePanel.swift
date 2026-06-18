import AppKit
import SwiftUI
import KeyboardShortcuts

/// Borderless, nonactivating floating panel that hosts the command palette.
/// Overriding `canBecomeKey` lets the search field accept typing while the app
/// stays in the background, so the app we paste into remains frontmost.
final class CommandPalettePanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

/// Owns the palette panel: summon/dismiss, remembers the previously-frontmost app,
/// and drives paste-back. Lives for the app's lifetime (created by AppDelegate).
@MainActor
final class PaletteController {
    static let shared = PaletteController()

    private var panel: CommandPalettePanel?
    private var previousApp: NSRunningApplication?

    func setup() {
        KeyboardShortcuts.onKeyDown(for: .togglePalette) { [weak self] in
            self?.toggle()
        }
    }

    func toggle() {
        if let panel, panel.isVisible {
            dismiss(paste: nil)
        } else {
            present()
        }
    }

    private func present() {
        // Remember who was frontmost so we can paste back into it.
        previousApp = NSWorkspace.shared.frontmostApplication

        let panel = panel ?? makePanel()
        self.panel = panel

        if let screen = NSScreen.main {
            let size = panel.frame.size
            let origin = NSPoint(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.midY - size.height / 2 + 100
            )
            panel.setFrameOrigin(origin)
        }
        // Key (so typing works) but NOT activating (prior app stays frontmost).
        panel.makeKeyAndOrderFront(nil)
    }

    /// Dismiss the panel. If `text` is non-nil, copy it and paste into the prior app.
    func dismiss(paste text: String?) {
        panel?.orderOut(nil)
        guard let text else { return }

        Paster.copyToPasteboard(text)

        // Make sure the app we came from is frontmost, then synthesize ⌘V.
        previousApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            if !Paster.synthesizePaste() {
                // No PostEvent permission yet — content is on the clipboard;
                // request the grant for next time. (User can ⌘V meanwhile.)
                Paster.requestPostEventAccess()
            }
        }
    }

    private func makePanel() -> CommandPalettePanel {
        let panel = CommandPalettePanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420))
        let root = PaletteView(
            onPaste: { [weak self] text in self?.dismiss(paste: text) },
            onClose: { [weak self] in self?.dismiss(paste: nil) }
        )
        panel.contentView = NSHostingView(rootView: root)
        return panel
    }
}
