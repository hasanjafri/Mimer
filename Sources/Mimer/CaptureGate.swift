import AppKit

/// Decides whether a freshly-copied clip should be recorded, based on pause state,
/// the user's excluded apps, and a built-in password-manager blocklist (belt-and-
/// suspenders with the `org.nspasteboard.ConcealedType` marker the monitor already honors).
enum CaptureGate {
    /// Never record while one of these is the frontmost app.
    static let passwordManagerBundleIDs: Set<String> = [
        "com.1password.1password",
        "com.1password.1password7",
        "com.agilebits.onepassword",
        "com.agilebits.onepassword4",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.Passwords",
        "org.keepassxc.keepassxc",
        "com.mssns.KeePassium",
        "com.dashlane.Dashlane",
        "com.lastpass.LastPass",
        "me.proton.pass.electron",
        "in.sinew.Walletx.osx",        // Enpass
        "com.enpass.Enpass",
        "com.nordpass.macos",
        "com.keepersecurity.mac",
        "com.markmcguill.strongbox.mac"
    ]

    /// Whether this specific app (by bundle id) is one we must never record from — the
    /// password-manager blocklist plus the user's exclusions. App-identity only (pause is
    /// separate), so the monitor can use it on app-activation events as well as at capture time.
    @MainActor
    static func isExcludedApp(_ bundleID: String?) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return passwordManagerBundleIDs.contains(bundleID) || Preferences.shared.excludedBundleIDs.contains(bundleID)
    }

    /// Evaluated at capture time (main thread, from the monitor's timer).
    @MainActor
    static func captureAllowed() -> Bool {
        if Preferences.shared.isPaused { return false }
        return !isExcludedApp(NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }
}
