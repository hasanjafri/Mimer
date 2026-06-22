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
    override func cancelOperation(_ sender: Any?) { PaletteController.shared.close() }
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

    func open(transformIndex: Int? = nil, stackIndices: [Int]? = nil) {
        guard !isPaletteVisible, !isDismissing else { return }   // don't reopen mid-paste-sequence
        previousApp = NSWorkspace.shared.frontmostApplication
        let panel = makePanel(transformIndex: transformIndex, stackIndices: stackIndices)   // fresh each open → field re-focuses + clean search
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

        panel?.delegate = nil          // avoid a dangling delegate / re-entrant resign during teardown
        panel?.orderOut(nil)
        panel = nil

        guard let text else { isDismissing = false; return }

        Paster.copyToPasteboard(text)
        activateThenPaste()
    }

    /// Dismiss and paste image bytes into the prior app (image-clip paste-back).
    func dismiss(pasteImage data: Data) {
        guard !isDismissing else { return }
        isDismissing = true
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil

        Paster.copyImageToPasteboard(data)
        activateThenPaste()
    }

    /// Re-focus the app we came from, then synthesize ⌘V — but only if that exact app is still
    /// frontmost after the focus settles. If another app stole the foreground in the window
    /// (e.g. a malicious app racing for a just-pasted secret), abort and leave the content on
    /// the clipboard for a manual ⌘V. Mirrors the paste-stack guard in `pasteNext`.
    private func activateThenPaste() {
        let target = previousApp
        if target?.isTerminated == false { target?.activate() }

        // Only auto-paste if already permitted; otherwise the clip is on the clipboard (the
        // user presses ⌘V). Never prompt for the grant mid-paste — the palette banner and
        // onboarding handle enabling it, in context.
        guard Paster.canPostEvents else { isDismissing = false; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            if let target, target.isTerminated ||
                NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier {
                self.isDismissing = false   // focus moved → don't paste into the wrong app
                return
            }
            Paster.synthesizePaste()
            self.isDismissing = false   // hold the reentrancy guard until the paste actually fires
        }
    }

    /// Paste the clip at `index` of the current history (used by the debug bridge).
    func pasteClip(at index: Int) {
        let items = ClipStore.shared.items
        guard items.indices.contains(index) else { return }
        let item = items[index]
        if item.kind == .image, let hash = item.blobHash, let data = ClipStore.shared.blobData(hash) {
            dismiss(pasteImage: data)
        } else {
            dismiss(paste: item.text)
        }
    }

    /// Paste several clips in order into the prior app (the paste-stack). Each clip is placed
    /// on the pasteboard and pasted, with a gap before the next so the target app keeps up.
    func dismiss(pasteSequence items: [String]) {
        guard !isDismissing else { return }
        guard items.count > 1 else { dismiss(paste: items.first); return }   // 0/1 → normal path
        isDismissing = true
        panel?.delegate = nil
        panel?.orderOut(nil)
        panel = nil

        let target = previousApp
        if target?.isTerminated == false { target?.activate() }
        guard Paster.canPostEvents else {
            // Can't auto-paste → assemble the whole stack on the clipboard (deterministic, all
            // items) for a manual ⌘V, rather than silently pasting an arbitrary one.
            _ = Paster.copyToPasteboard(items.joined(separator: "\n"))
            isDismissing = false
            return
        }
        pasteNext(items, index: 0, target: target, initialDelay: 0.12)   // let the prior app focus first
    }

    private func pasteNext(_ items: [String], index: Int, target: NSRunningApplication?, initialDelay: TimeInterval = 0) {
        guard index < items.count else { isDismissing = false; return }
        _ = Paster.copyToPasteboard(items[index])
        DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) { [weak self] in
            guard let self else { return }
            // Abort if the intended app went away or is no longer frontmost — never paste the
            // rest of the stack into whatever happens to be up front now.
            if let target, target.isTerminated ||
                NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier {
                self.isDismissing = false
                return
            }
            _ = Paster.synthesizePaste()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {   // gap so the app processes each paste
                self.pasteNext(items, index: index + 1, target: target)
            }
        }
    }

    // Introspection (used by the debug bridge).
    var isPaletteVisible: Bool { panel?.isVisible ?? false }
    var isPaletteKey: Bool { panel?.isKeyWindow ?? false }
    var firstResponderDescription: String {
        guard let fr = panel?.firstResponder else { return "nil" }
        return String(describing: type(of: fr))
    }

    private func makePanel(transformIndex: Int? = nil, stackIndices: [Int]? = nil) -> CommandPalettePanel {
        let panel = CommandPalettePanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 440))
        panel.delegate = self
        let root = PaletteView(
            onPaste: { [weak self] text in self?.dismiss(paste: text) },
            onPasteImage: { [weak self] data in self?.dismiss(pasteImage: data) },
            onPasteSequence: { [weak self] texts in self?.dismiss(pasteSequence: texts) },
            onClose: { [weak self] in self?.dismiss(paste: nil) },
            initialTransformIndex: transformIndex,
            initialStackIndices: stackIndices
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
