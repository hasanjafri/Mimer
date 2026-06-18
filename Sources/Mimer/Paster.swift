import AppKit
import Carbon.HIToolbox  // kVK_ANSI_V

/// Places content on the pasteboard and (optionally) synthesizes ⌘V into the
/// frontmost app. Auto-paste uses `CGEvent.post`, gated by the PostEvent TCC
/// service (`kTCCServicePostEvent`) — NOT the Accessibility AX API and NOT
/// AppleScript. This is sandbox-compatible and the approach Maccy ships.
enum Paster {
    /// Whether we currently hold permission to post keyboard events.
    static var canPostEvents: Bool { CGPreflightPostEventAccess() }

    /// Shows the system PostEvent permission prompt (once). Returns current grant.
    @discardableResult
    static func requestPostEventAccess() -> Bool { CGRequestPostEventAccess() }

    static func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Synthesize ⌘V into whatever app is frontmost. Returns false if we lack
    /// PostEvent permission (caller should fall back to "it's on the clipboard").
    @discardableResult
    static func synthesizePaste() -> Bool {
        guard CGPreflightPostEventAccess() else { return false }
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey = CGKeyCode(kVK_ANSI_V)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else { return false }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
        return true
    }
}
