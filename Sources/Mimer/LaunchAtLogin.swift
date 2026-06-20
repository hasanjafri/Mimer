import Foundation
import ServiceManagement

/// Launch-at-login via SMAppService (macOS 13+). The registration itself is the
/// source of truth — no mirrored UserDefaults flag to drift out of sync.
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        do {
            switch (enabled, SMAppService.mainApp.status) {
            case (true, let s) where s != .enabled: try SMAppService.mainApp.register()
            case (false, .enabled): try SMAppService.mainApp.unregister()
            default: break
            }
        } catch {
            NSLog("Mimer LaunchAtLogin \(enabled ? "register" : "unregister") failed: \(error)")
        }
    }
}
