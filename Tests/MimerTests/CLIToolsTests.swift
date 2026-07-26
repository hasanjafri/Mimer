import XCTest
@testable import Mimer

/// MimerTests is hosted inside Mimer.app, so `Bundle.main` is the app bundle — which lets us
/// assert the CLI/MCP binaries are actually embedded (Contents/Resources) and executable.
/// Guards the distribution wiring so a dropped copy phase fails CI.
final class CLIToolsTests: XCTestCase {
    private var hostIsApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    func testToolsAreEmbeddedAndExecutable() throws {
        try XCTSkipUnless(hostIsApp, "test host isn't the app bundle (\(Bundle.main.bundleURL.lastPathComponent))")
        XCTAssertTrue(CLITools.isAvailable, "mimer/mimer-mcp not embedded in the app bundle")
        for name in CLITools.toolNames {
            let url = try XCTUnwrap(CLITools.bundledURL(name), "\(name) missing from bundle")
            XCTAssertTrue(FileManager.default.isExecutableFile(atPath: url.path))
            XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "Resources",
                           "\(name) must live in Contents/Resources, not MacOS (case-collision with Mimer)")
        }
    }
}
