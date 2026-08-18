import AppKit
import SwiftUI

/// Owns the hover preview card: when it appears, where it goes, and when it must be gone.
///
/// The card lives in its own click-through panel rather than inside the palette or the menu, for
/// three reasons: the menu dropdown is 320pt wide and could never host it, the palette must not
/// resize under the pointer while you are reading a row, and a panel can never steal key focus
/// from the search field (`canBecomeKey` is false, mouse events pass straight through).
@MainActor
final class ClipPeek {
    static let shared = ClipPeek()

    /// Every timer here runs in `.common` modes, not `.default`: hovering a list puts the run
    /// loop into event-tracking, where a default-mode timer simply never fires — the card would
    /// wait for you to stop interacting to appear. Same reason `ClipboardMonitor` polls on
    /// `.common`.
    ///
    /// Dwell before a card appears. Hovering is how you *scan* a list, so the card waits until
    /// you have actually settled on a row; once one is up, moving to the next row swaps it
    /// instantly (the standard warm-tooltip behaviour).
    private static let hoverDelay: TimeInterval = 0.4
    private static let keyboardDelay: TimeInterval = 0.55

    private enum Anchor {
        case pointer(NSPoint), hostCenter
        var isPointer: Bool { if case .pointer = self { return true }; return false }
    }

    private var panel: ClipPeekPanel?
    private var dwell: Timer?
    private var watchdog: Timer?
    private weak var host: NSWindow?
    private var pending: (id: UUID, card: ClipInspectorCard, anchor: Anchor)?
    private var shownID: UUID?
    private var anchoredToPointer = false
    private var anchorPoint: NSPoint = .zero
    private var maskedWhenShown = true
    private var exitGrace: Timer?

    var isVisible: Bool { panel?.isVisible ?? false }
    /// Recent state transitions and why — surfaced in the debug state file so the self-test loop
    /// can see *why* a card appeared or went away without a human watching the screen.
    private(set) var eventLog: [String] = []

    private func log(_ event: String) {
        eventLog.append(event)
        if eventLog.count > 10 { eventLog.removeFirst() }
    }

    // MARK: - Entry points

    /// The pointer settled on a row. Anchored to the pointer, beside the window it is over.
    func hover(_ item: ClipItem, query: String = "", action: ClipAction? = nil, revealed: Bool = false) {
        let pointer = NSEvent.mouseLocation
        show(item, query: query, action: action, revealed: revealed,
             host: window(under: pointer), anchor: .pointer(pointer), delay: Self.hoverDelay)
    }

    /// The keyboard selection moved in the palette. Anchored beside the palette instead of the
    /// pointer (which is nowhere near the list), so the card reads as a detail pane.
    func select(_ item: ClipItem, query: String = "", action: ClipAction? = nil, revealed: Bool = false) {
        guard let palette = PaletteController.shared.panelWindow else { return }
        show(item, query: query, action: action, revealed: revealed,
             host: palette, anchor: .hostCenter, delay: Self.keyboardDelay)
    }

    /// The pointer left `id`'s row. Ignored if a different row has since taken over, so moving
    /// between rows never flickers.
    func endHover(_ id: UUID) {
        guard anchoredToPointer else { return }   // a keyboard-anchored card isn't the pointer's to dismiss
        guard pending?.id == id || shownID == id else { return }
        // Leave on a short grace: moving between two rows fires exit-then-enter, and AppKit can
        // emit a spurious exit mid-row. A real departure still reads as instant.
        exitGrace?.invalidate()
        exitGrace = schedule(after: 0.12, .endHover)
    }

    #if DEBUG
    /// Headless self-test path: show a card with no pointer and no palette (anchored to the
    /// screen) so the dwell, the watchdog, and the layout can be verified without a live mouse
    /// or a window that has to keep focus. Never reachable in a release build.
    func debugPeek(_ item: ClipItem, action: ClipAction? = nil) {
        let palette = PaletteController.shared.panelWindow
        show(item, query: "", action: action, revealed: false, host: palette,
             anchor: .hostCenter, delay: Self.keyboardDelay)   // never pointer-anchored: no live mouse here
    }
    #endif

    func hide(reason: String = "hide") {
        exitGrace?.invalidate(); exitGrace = nil
        dwell?.invalidate(); dwell = nil
        watchdog?.invalidate(); watchdog = nil
        pending = nil
        shownID = nil
        if panel?.isVisible == true { log("hide:\(reason)") }
        panel?.orderOut(nil)
    }

    // MARK: - Show

    private func show(_ item: ClipItem, query: String, action: ClipAction?, revealed: Bool,
                      host: NSWindow?, anchor: Anchor, delay: TimeInterval) {
        guard Preferences.shared.previewOnHover else { return }
        exitGrace?.invalidate(); exitGrace = nil   // before the early return: re-entering the same row cancels its pending exit
        guard shownID != item.id || !isVisible else { return }   // already showing this clip

        let inspector = ClipInspector.make(for: item,
                                           maskSecrets: Preferences.shared.maskSecrets,
                                           revealed: revealed,
                                           action: action,
                                           query: query)
        log("show \(anchor.isPointer ? "hover" : "keyboard")")
        self.host = host
        anchoredToPointer = anchor.isPointer
        maskedWhenShown = Preferences.shared.maskSecrets
        if case .pointer(let point) = anchor { anchorPoint = point }
        pending = (item.id, ClipInspectorCard(inspector: inspector), anchor)

        dwell?.invalidate()
        if isVisible {
            present()          // warm: swap content with no second wait
        } else {
            dwell = schedule(after: delay, .present)
        }
    }

    private func present() {
        guard let pending else { return }
        dwell?.invalidate(); dwell = nil

        let panel = self.panel ?? ClipPeekPanel()
        self.panel = panel

        let hosting = NSHostingView(rootView: pending.card)
        panel.contentView = hosting
        hosting.layoutSubtreeIfNeeded()

        let visible = screen(for: pending.anchor)?.visibleFrame ?? .zero
        var size = hosting.fittingSize
        size.width = ClipInspectorCard.width
        size.height = min(max(size.height, 80), max(120, visible.height - 40))

        let pointer: NSPoint
        switch pending.anchor {
        case .pointer(let p): pointer = p
        case .hostCenter: pointer = NSPoint(x: host?.frame.midX ?? visible.midX, y: host?.frame.midY ?? visible.midY)
        }
        panel.setFrame(ClipPeekLayout.frame(size: size, host: host?.frame, pointer: pointer, visible: visible),
                       display: true)

        if !panel.isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
        shownID = pending.id
        self.pending = nil
        log("shown host=\(host == nil ? "none" : "yes") pointer=\(anchoredToPointer)")
        startWatchdog()
    }

    // MARK: - Staying honest about when to disappear

    /// AppKit does not reliably deliver a hover-exit when the pointer leaves a window (the menu
    /// list already works around this), and a menu or palette can vanish out from under the card
    /// entirely. So while a card is up, keep checking that its reason to exist still holds.
    private func startWatchdog() {
        watchdog?.invalidate()
        watchdog = schedule(after: 0.25, repeats: true, .watchdog)
    }

    private func checkStillValid() {
        guard isVisible else { watchdog?.invalidate(); watchdog = nil; return }
        guard Preferences.shared.previewOnHover else { hide(reason: "pref-off"); return }
        // Fail closed on a masking change: the card on screen was rendered under the old setting,
        // and if masking was just switched on it is showing a secret it no longer should.
        guard Preferences.shared.maskSecrets == maskedWhenShown else { hide(reason: "masking-changed"); return }

        guard let host else {
            // No host window to watch (the pointer was over something we couldn't identify).
            // Fall back to the pointer itself, so a missed hover-exit can't strand the card.
            if anchoredToPointer, hypot(NSEvent.mouseLocation.x - anchorPoint.x,
                                        NSEvent.mouseLocation.y - anchorPoint.y) > 60 {
                hide(reason: "pointer-moved")
            }
            return
        }
        guard host.isVisible else { hide(reason: "host-gone"); return }
        // A pointer-anchored card belongs to the pointer: once it leaves the window the card is
        // stale, even if the row never delivered its exit. Keyboard-anchored cards ignore this.
        if anchoredToPointer, !host.frame.insetBy(dx: -4, dy: -4).contains(NSEvent.mouseLocation) {
            hide(reason: "pointer-left")
        }
    }

    /// The window the pointer is over. Prefer the frontmost/most specific one — a menu or panel
    /// sits above (and inside) whatever is behind it.
    /// What a scheduled tick does. An enum rather than a closure so nothing non-Sendable is
    /// captured by the timer block.
    private enum Tick: Sendable { case present, endHover, watchdog }

    private func schedule(after delay: TimeInterval, repeats: Bool = false, _ tick: Tick) -> Timer {
        let timer = Timer(timeInterval: delay, repeats: repeats) { _ in
            MainActor.assumeIsolated {
                switch tick {
                case .present: ClipPeek.shared.present()
                case .endHover: ClipPeek.shared.hide(reason: "hover-exit")
                case .watchdog: ClipPeek.shared.checkStillValid()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func window(under point: NSPoint) -> NSWindow? {
        NSApp.windows
            .filter { $0.isVisible && $0 !== panel && $0.frame.contains(point) }
            .max { a, b in
                a.level.rawValue != b.level.rawValue
                    ? a.level.rawValue < b.level.rawValue
                    : a.frame.width * a.frame.height > b.frame.width * b.frame.height
            }
    }

    private func screen(for anchor: Anchor) -> NSScreen? {
        let point: NSPoint
        switch anchor {
        case .pointer(let p): point = p
        case .hostCenter: point = host.map { NSPoint(x: $0.frame.midX, y: $0.frame.midY) } ?? NSEvent.mouseLocation
        }
        return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }
}

/// Where the card goes: beside its host window (never on top of the list you are reading),
/// vertically centred on the anchor, always fully on screen. Pure so the flip and clamp
/// behaviour is testable.
enum ClipPeekLayout {
    static func frame(size: NSSize, host: NSRect?, pointer: NSPoint, visible: NSRect, gap: CGFloat = 10) -> NSRect {
        var x: CGFloat
        if let host {
            let right = host.maxX + gap
            let left = host.minX - gap - size.width
            if right + size.width <= visible.maxX {
                x = right
            } else if left >= visible.minX {
                x = left                                  // no room on the right — flip
            } else {
                x = visible.maxX - size.width - gap       // no room either side — hug the edge
            }
        } else {
            x = pointer.x + 16
        }
        let maxX = max(visible.minX + gap, visible.maxX - size.width - gap)
        x = min(max(x, visible.minX + gap), maxX)

        let maxY = max(visible.minY + gap, visible.maxY - size.height - gap)
        let y = min(max(pointer.y - size.height / 2, visible.minY + gap), maxY)

        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}

/// Borderless, non-activating, click-through panel for the card. It must never take key focus
/// (the palette's search field keeps it) and never intercept the pointer (the row underneath
/// stays hovered), so `canBecomeKey` is false and mouse events pass through.
final class ClipPeekPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: ClipInspectorCard.width, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        // One above the menu dropdown's own level (.popUpMenu), so a card that has to overlap
        // the menu on a small screen still wins.
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false          // the palette is used while another app is frontmost
        isReleasedWhenClosed = false
        animationBehavior = .none
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
