import AppKit

/// The `mimer` and `mimer-mcp` binaries ship inside the app bundle (Contents/Resources —
/// not Contents/MacOS, where `mimer` would collide with the app's own `Mimer` executable on
/// case-insensitive APFS). This resolves them and offers to symlink them onto the PATH.
enum CLITools {
    static let toolNames = ["mimer", "mimer-mcp"]
    private static let binDir = URL(fileURLWithPath: "/usr/local/bin")

    /// The bundled binary, if present and executable.
    static func bundledURL(_ name: String) -> URL? {
        guard let res = Bundle.main.resourceURL else { return nil }
        let url = res.appendingPathComponent(name)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    /// True when both tools are present in the bundle (they aren't in some dev/test hosts).
    static var isAvailable: Bool { toolNames.allSatisfy { bundledURL($0) != nil } }

    enum Outcome {
        case installed([String])   // symlinked these names into /usr/local/bin
        case manual(String)        // couldn't write there; here's the command to do it by hand
        case unavailable           // binaries not in this build
    }

    /// Symlink the bundled tools into /usr/local/bin. Falls back to returning the manual
    /// command (never escalates privileges itself) when that directory isn't writable.
    static func install() -> Outcome {
        let fm = FileManager.default
        let tools = toolNames.compactMap { name in bundledURL(name).map { (name, $0) } }
        guard !tools.isEmpty else { return .unavailable }
        guard fm.fileExists(atPath: binDir.path), fm.isWritableFile(atPath: binDir.path) else {
            return .manual(manualCommand(tools))
        }
        var linked: [String] = []
        for (name, src) in tools {
            let dest = binDir.appendingPathComponent(name)
            try? fm.removeItem(at: dest)                       // replace a prior symlink if any
            do {
                try fm.createSymbolicLink(at: dest, withDestinationURL: src)
                linked.append(name)
            } catch {
                return .manual(manualCommand(tools))
            }
        }
        return .installed(linked)
    }

    private static func manualCommand(_ tools: [(String, URL)]) -> String {
        tools.map { name, src in "ln -sf \"\(src.path)\" /usr/local/bin/\(name)" }.joined(separator: "\n")
    }
}
