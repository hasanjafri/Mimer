import Foundation
import Combine

/// User settings, persisted in UserDefaults.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    /// Maximum clips kept in history (storage cap).
    @Published var historyLimit: Int {
        didSet { defaults.set(historyLimit, forKey: Keys.historyLimit) }
    }

    /// Maximum clips shown at once in the menu bar before scrolling. Drives the
    /// dropdown's height (capped at the screen height).
    @Published var visibleRows: Int {
        didSet { defaults.set(visibleRows, forKey: Keys.visibleRows) }
    }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let historyLimit = "historyLimit"
        static let visibleRows = "visibleRows"
    }

    private init() {
        historyLimit = defaults.object(forKey: Keys.historyLimit) as? Int ?? 200
        visibleRows = defaults.object(forKey: Keys.visibleRows) as? Int ?? 15
    }
}
