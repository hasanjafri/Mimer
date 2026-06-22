import Foundation
import Combine

/// User settings, persisted in UserDefaults. Main-actor-isolated: it's UI state, read/written
/// only from the main thread (SwiftUI views, the @MainActor ClipStore, the menu bar).
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    /// Maximum clips kept in history (storage cap).
    @Published var historyLimit: Int {
        didSet { defaults.set(historyLimit, forKey: Keys.historyLimit) }
    }

    /// Maximum clips shown at once in the menu bar before scrolling.
    @Published var visibleRows: Int {
        didSet { defaults.set(visibleRows, forKey: Keys.visibleRows) }
    }

    /// Whether the first-run onboarding has been completed.
    @Published var hasOnboarded: Bool {
        didSet { defaults.set(hasOnboarded, forKey: Keys.hasOnboarded) }
    }

    /// When true, the clipboard monitor stops recording new clips.
    @Published var isPaused: Bool {
        didSet { defaults.set(isPaused, forKey: Keys.isPaused) }
    }

    /// Bundle IDs of apps Mimer won't record from (while they're frontmost).
    @Published var excludedBundleIDs: Set<String> {
        didSet { defaults.set(Array(excludedBundleIDs), forKey: Keys.excludedBundleIDs) }
    }

    /// Mask detected secrets (API keys, tokens, …) in the list. They're still stored and
    /// pasted in full — only the on-screen display is masked (anti shoulder-surf/screenshare).
    @Published var maskSecrets: Bool {
        didSet { defaults.set(maskSecrets, forKey: Keys.maskSecrets) }
    }

    // MARK: - Developer integrations (⌘O "act on") — all optional/empty by default.

    /// Remote base for git-SHA clips, e.g. `github.com/acme/app` → opens `…/commit/<sha>`.
    @Published var gitRemoteBase: String {
        didSet { defaults.set(gitRemoteBase, forKey: Keys.gitRemoteBase) }
    }
    /// Issue-tracker URL with a `{KEY}` placeholder, e.g. `https://acme.atlassian.net/browse/{KEY}`.
    @Published var issueTrackerTemplate: String {
        didSet { defaults.set(issueTrackerTemplate, forKey: Keys.issueTrackerTemplate) }
    }
    /// Editor for `file:line` clips ("" = none, else a `ClipAction.DevConfig.Editor` raw value).
    @Published var editorKind: String {
        didSet { defaults.set(editorKind, forKey: Keys.editorKind) }
    }

    /// The structured config consumed by `ClipAction` (empty/invalid fields → disabled).
    var devConfig: ClipAction.DevConfig {
        ClipAction.DevConfig(
            gitRemoteBase: gitRemoteBase.trimmingCharacters(in: .whitespaces).isEmpty ? nil : gitRemoteBase,
            issueTrackerTemplate: issueTrackerTemplate.contains("{KEY}") ? issueTrackerTemplate : nil,
            editor: ClipAction.DevConfig.Editor(rawValue: editorKind)
        )
    }

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let historyLimit = "historyLimit"
        static let visibleRows = "visibleRows"
        static let hasOnboarded = "hasOnboarded"
        static let isPaused = "isPaused"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let maskSecrets = "maskSecrets"
        static let gitRemoteBase = "gitRemoteBase"
        static let issueTrackerTemplate = "issueTrackerTemplate"
        static let editorKind = "editorKind"
    }

    private init() {
        historyLimit = min(1000, max(25, defaults.object(forKey: Keys.historyLimit) as? Int ?? 200))
        visibleRows = min(40, max(5, defaults.object(forKey: Keys.visibleRows) as? Int ?? 15))
        hasOnboarded = defaults.bool(forKey: Keys.hasOnboarded)
        isPaused = defaults.bool(forKey: Keys.isPaused)
        excludedBundleIDs = Set(defaults.stringArray(forKey: Keys.excludedBundleIDs) ?? [])
        maskSecrets = defaults.object(forKey: Keys.maskSecrets) as? Bool ?? true   // default on
        gitRemoteBase = defaults.string(forKey: Keys.gitRemoteBase) ?? ""
        issueTrackerTemplate = defaults.string(forKey: Keys.issueTrackerTemplate) ?? ""
        editorKind = defaults.string(forKey: Keys.editorKind) ?? ""
    }
}
