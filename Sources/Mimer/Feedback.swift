import Foundation

/// Builds the "Send Feedback" destinations. Mimer collects no telemetry, so a
/// prefilled GitHub issue is how a user's experience reaches us — this fills in
/// the version + macOS fields the bug form asks for so the report is one click
/// of friction lighter. Opens a URL only; nothing is sent in the background.
enum Feedback {
    private static let repo = "https://github.com/hasanjafri/Mimer"

    /// Deep-links the bug-report issue form with the environment prefilled.
    static var bugReportURL: URL {
        var comps = URLComponents(string: "\(repo)/issues/new")!
        comps.queryItems = [
            URLQueryItem(name: "template", value: "bug_report.yml"),
            URLQueryItem(name: "mimer-version", value: appVersion),
            URLQueryItem(name: "macos-version", value: osDescription),
        ]
        return comps.url!
    }

    /// Open-ended feedback and feature ideas live in Discussions.
    static let discussionsURL = URL(string: "\(repo)/discussions")!

    /// Marketing version only (e.g. "0.2.2") — the build number isn't useful in a report.
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    /// e.g. "14.5 (Apple silicon)" — matches the bug form's placeholder.
    static var osDescription: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let version = "\(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
        return "\(version) (\(cpuDescription))"
    }

    private static var cpuDescription: String {
        // Under Rosetta on Apple silicon, uname reports "x86_64", which would
        // mislabel the report as Intel — consult the translation flag first.
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0, translated == 1 {
            return "Apple silicon"
        }
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
        return machine.hasPrefix("arm") ? "Apple silicon" : "Intel"
    }
}
