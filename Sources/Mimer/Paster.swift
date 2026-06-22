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

    /// Whether a synthetic paste should fire: only when a known target app is still alive AND
    /// still frontmost, so a clip never lands in an app that grabbed focus during the delay.
    /// Pure + unit-testable; callers pass PIDs read from `NSRunningApplication` at fire time.
    static func shouldAutoPaste(targetPID: pid_t?, targetTerminated: Bool, frontmostPID: pid_t?) -> Bool {
        guard let targetPID, !targetTerminated else { return false }   // unknown / gone target → fail closed
        return frontmostPID == targetPID
    }

    /// Returns whether the write actually landed, so callers can avoid confirming
    /// a copy that didn't happen. Discardable — most callers don't care.
    @discardableResult
    static func copyToPasteboard(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        // Stamp our own writes so the monitor skips them (no capture feedback loop).
        let restored = NSPasteboard.PasteboardType("org.nspasteboard.RestoredType")
        pb.declareTypes([.string, restored], owner: nil)
        return pb.setString(text, forType: .string)
    }

    /// Put image bytes back on the pasteboard (image-clip paste-back). Detects PNG vs TIFF from
    /// the magic bytes and writes the matching type; stamps RestoredType so the monitor skips it.
    @discardableResult
    static func copyImageToPasteboard(_ data: Data) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        let restored = NSPasteboard.PasteboardType("org.nspasteboard.RestoredType")
        let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47])   // \x89PNG
        let type: NSPasteboard.PasteboardType = isPNG ? .png : .tiff
        pb.declareTypes([type, restored], owner: nil)
        return pb.setData(data, forType: type)
    }

    /// Synthesize ⌘V into whatever app is frontmost. Returns false if we lack
    /// PostEvent permission (caller should fall back to "it's on the clipboard").
    @discardableResult
    static func synthesizePaste() -> Bool {
        guard CGPreflightPostEventAccess() else { return false }
        // .privateState avoids inheriting the user's live modifier state (e.g. a
        // still-held ⇧ from ⇧⌘V turning the synthetic ⌘V into ⇧⌘V).
        let source = CGEventSource(stateID: .privateState)
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
