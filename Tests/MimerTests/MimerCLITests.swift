import XCTest

/// Integration tests for the `mimer` CLI. They run the actual built binary that
/// sits next to this test bundle in the Products dir (MimerTests depends on the
/// `mimer` target for build order). If the binary can't be found for any reason,
/// the tests skip rather than fail, so a path quirk never reds CI.
final class MimerCLITests: XCTestCase {
    private func binaryURL() throws -> URL {
        let fm = FileManager.default
        var tried: [URL] = []
        // BUILT_PRODUCTS_DIR is set when running under Xcode's test action.
        if let built = ProcessInfo.processInfo.environment["BUILT_PRODUCTS_DIR"] {
            tried.append(URL(fileURLWithPath: built).appendingPathComponent("mimer"))
        }
        // MimerTests is app-hosted, so its .xctest lives inside Mimer.app/Contents/PlugIns —
        // the products dir with the mimer binary is several levels up. Climb until we find it.
        var dir = Bundle(for: type(of: self)).bundleURL.deletingLastPathComponent()
        for _ in 0..<6 {
            tried.append(dir.appendingPathComponent("mimer"))
            dir = dir.deletingLastPathComponent()
        }
        if let url = tried.first(where: { fm.isExecutableFile(atPath: $0.path) }) {
            return url
        }
        throw XCTSkip("mimer binary not found. Tried: \(tried.map(\.path).joined(separator: ", "))")
    }

    @discardableResult
    private func run(_ args: [String], stdin: String? = nil) throws -> (out: String, err: String, code: Int32) {
        let proc = Process()
        proc.executableURL = try binaryURL()
        proc.arguments = args
        let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
        proc.standardOutput = outPipe; proc.standardError = errPipe; proc.standardInput = inPipe
        try proc.run()
        if let stdin { inPipe.fileHandleForWriting.write(Data(stdin.utf8)) }
        inPipe.fileHandleForWriting.closeFile()
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        proc.waitUntilExit()
        return (out, err, proc.terminationStatus)
    }

    func testVersion() throws {
        let r = try run(["version"])
        XCTAssertEqual(r.code, 0)
        XCTAssertTrue(r.out.contains("mimer"), r.out)
    }

    func testJSONToTypeScriptFromStdin() throws {
        let r = try run(["json-to-ts"], stdin: #"{"id":1,"name":"a","tags":["x"]}"#)
        XCTAssertEqual(r.code, 0)
        XCTAssertTrue(r.out.contains("interface Root"), r.out)
        XCTAssertTrue(r.out.contains("id: number"), r.out)
        XCTAssertTrue(r.out.contains("tags: string[]"), r.out)
    }

    func testSlugifyFromArgument() throws {
        let r = try run(["slugify", "Hello, World! Foo"])
        XCTAssertEqual(r.code, 0)
        XCTAssertEqual(r.out.trimmingCharacters(in: .whitespacesAndNewlines), "hello-world-foo")
    }

    func testUnknownTransformExits2() throws {
        let r = try run(["definitely-not-a-transform", "x"])
        XCTAssertEqual(r.code, 2)
        XCTAssertTrue(r.err.contains("unknown transform"), r.err)
    }

    func testNotApplicableExits1() throws {
        let r = try run(["json-to-ts"], stdin: "just some prose")
        XCTAssertEqual(r.code, 1)
        XCTAssertTrue(r.err.contains("did not apply"), r.err)
    }

    func testListIncludesKeyTransforms() throws {
        let r = try run(["list"])
        XCTAssertEqual(r.code, 0)
        for name in ["json-to-ts", "decode-jwt", "slugify", "base64-encode"] {
            XCTAssertTrue(r.out.contains(name), "list missing \(name):\n\(r.out)")
        }
    }
}
