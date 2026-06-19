import AppKit

/// Decides whether a freshly-copied clip should be recorded, based on pause state,
/// the user's excluded apps, and a built-in password-manager blocklist (belt-and-
/// suspenders with the `org.nspasteboard.ConcealedType` marker the monitor already honors).
enum CaptureGate {
    /// Never record while one of these is the frontmost app.
    static let passwordManagerBundleIDs: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.Passwords",
        "org.keepassxc.keepassxc",
        "com.dashlane.Dashlane",
        "com.lastpass.LastPass",
        "com.mssns.KeePassium"
    ]

    /// Evaluated at capture time (main thread, from the monitor's timer).
    static func captureAllowed() -> Bool {
        if Preferences.shared.isPaused { return false }
        let frontID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        if !frontID.isEmpty {
            if passwordManagerBundleIDs.contains(frontID) { return false }
            if Preferences.shared.excludedBundleIDs.contains(frontID) { return false }
        }
        return true
    }
}
