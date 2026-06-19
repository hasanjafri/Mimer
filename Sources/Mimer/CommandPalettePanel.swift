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
        animationBehavior = .none          // instant show/hide — snappy, predictable
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { orderOut(nil) }
}

/// Owns the palette panel: summon/dismiss, remembers the previously-frontmost
/// app, drives paste-back, and closes on click-away. Lives for the app's lifetime.
@MainActor
final class PaletteController: NSObject {
    static let shared = PaletteController()

    private var panel: CommandPalettePanel?
    private var previousApp: NSRunningApplication?
    private var isDismissing = false

    func setup() {
        KeyboardShortcuts.onKeyDown(for: .togglePalette) { [weak self] in
            self?.toggle()
        }
    }

    func toggle() {
        if isPaletteVisible { dismiss(paste: nil) } else { open() }
    }

    func open() {
        guard !isPaletteVisible else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        let panel = makePanel()   // fresh each open → field re-focuses + clean search
        self.panel = panel
        if let screen = NSScreen.main {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.midY - size.height / 2 + 100
            ))
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func close() { dismiss(paste: nil) }

    /// Dismiss the panel. If `text` is non-nil, copy it and paste into the prior app.
    func dismiss(paste text: String?) {
        guard !isDismissing else { return }
        isDismissing = true
        defer { isDismissing = false }

        panel?.orderOut(nil)
        panel = nil
        guard let text else { return }

        Paster.copyToPasteboard(text)
        previousApp?.activate()
        // Only auto-paste if already permitted; otherwise the clip is on the
        // clipboard (the user presses ⌘V). Never prompt for the grant mid-paste —
        // the palette banner and onboarding handle enabling it, in context.
        guard Paster.canPostEvents else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            Paster.synthesizePaste()
        }
    }

    /// Paste the clip at `index` of the current history (used by the debug bridge).
    func pasteClip(at index: Int) {
        let items = ClipStore.shared.items
        guard items.indices.contains(index) else { return }
        dismiss(paste: items[index].text)
    }

    // Introspection (used by the debug bridge).
    var isPaletteVisible: Bool { panel?.isVisible ?? false }
    var isPaletteKey: Bool { panel?.isKeyWindow ?? false }
    var firstResponderDescription: String {
        guard let fr = panel?.firstResponder else { return "nil" }
        return String(describing: type(of: fr))
    }

    private func makePanel() -> CommandPalettePanel {
        let panel = CommandPalettePanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 440))
        panel.delegate = self
        let root = PaletteView(
            onPaste: { [weak self] text in self?.dismiss(paste: text) },
            onClose: { [weak self] in self?.dismiss(paste: nil) }
        )
        panel.contentView = NSHostingView(rootView: root)
        return panel
    }
}

extension PaletteController: NSWindowDelegate {
    /// Click-away or app-switch closes the palette (the fix for "it won't close").
    func windowDidResignKey(_ notification: Notification) {
        guard !isDismissing, isPaletteVisible else { return }
        dismiss(paste: nil)
    }
}
