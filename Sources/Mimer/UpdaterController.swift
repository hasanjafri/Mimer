import Foundation
import Sparkle

/// Sparkle auto-update controller. The standard updater starts on launch (it
/// honors `SUEnableAutomaticChecks` / `SUFeedURL` / `SUPublicEDKey` from Info.plist);
/// `checkForUpdates()` backs the menu's "Check for Updates…" item.
@MainActor
final class UpdaterController {
    static let shared = UpdaterController()

    private let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func checkForUpdates() { controller.updater.checkForUpdates() }
}
