import XCTest

/// Integration tests for the `mimer-mcp` server: drive the real built binary over stdio
/// with JSON-RPC and check the protocol. Skips (never fails) if the binary isn't found.
final class MimerMCPTests: XCTestCase {
    private func binaryURL() throws -> URL {
        let fm = FileManager.default
        var tried: [URL] = []
        if let built = ProcessInfo.processInfo.environment["BUILT_PRODUCTS_DIR"] {
            tried.append(URL(fileURLWithPath: built).appendingPathComponent("mimer-mcp"))
        }
        var dir = Bundle(for: type(of: self)).bundleURL.deletingLastPathComponent()
        for _ in 0..<6 {
            tried.append(dir.appendingPathComponent("mimer-mcp"))
            dir = dir.deletingLastPathComponent()
        }
        if let url = tried.first(where: { fm.isExecutableFile(atPath: $0.path) }) { return url }
        throw XCTSkip("mimer-mcp binary not found. Tried: \(tried.map(\.path).joined(separator: ", "))")
    }

    /// Feed newline-delimited JSON-RPC lines, return the parsed response objects.
    private func exchange(_ requests: [String]) throws -> [[String: Any]] {
        let proc = Process()
        proc.executableURL = try binaryURL()
        let inPipe = Pipe(), outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        try proc.run()
        inPipe.fileHandleForWriting.write(Data((requests.joined(separator: "\n") + "\n").utf8))
        inPipe.fileHandleForWriting.closeFile()
        let out = outPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(decoding: out, as: UTF8.self)
            .split(separator: "\n")
            .compactMap { line in
                (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
            }
    }

    func testInitializeAndToolsList() throws {
        let responses = try exchange([
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}"#,
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
        ])
        // The notification produces no response, so exactly two replies come back.
        XCTAssertEqual(responses.count, 2)
        let initResult = responses.first(where: { ($0["id"] as? Int) == 1 })?["result"] as? [String: Any]
        XCTAssertEqual((initResult?["serverInfo"] as? [String: Any])?["name"] as? String, "mimer")
        let tools = (responses.first(where: { ($0["id"] as? Int) == 2 })?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        let names = Set((tools ?? []).compactMap { $0["name"] as? String })
        XCTAssertEqual(names, ["list_transforms", "transform", "recent_clips", "search_clips"])
    }

    func testTransformToolCall() throws {
        let responses = try exchange([
            #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"transform","arguments":{"name":"json-to-ts","text":"{\"id\":1}"}}}"#,
        ])
        let result = responses.first?["result"] as? [String: Any]
        XCTAssertEqual(result?["isError"] as? Bool, false)
        let text = ((result?["content"] as? [[String: Any]])?.first)?["text"] as? String
        XCTAssertTrue(text?.contains("interface Root") == true, text ?? "nil")
    }

    func testUnknownTransformIsToolError() throws {
        let responses = try exchange([
            #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"transform","arguments":{"name":"nope","text":"x"}}}"#,
        ])
        let result = responses.first?["result"] as? [String: Any]
        XCTAssertEqual(result?["isError"] as? Bool, true)
    }

    // With the app not running under test, history tools return the graceful "off" note,
    // never data — the default-off posture from the server's side.
    func testRecentClipsWithoutAppReturnsGracefulNote() throws {
        let responses = try exchange([
            #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"recent_clips","arguments":{}}}"#,
        ])
        let result = responses.first?["result"] as? [String: Any]
        XCTAssertEqual(result?["isError"] as? Bool, false)
        let text = ((result?["content"] as? [[String: Any]])?.first)?["text"] as? String
        XCTAssertTrue(text?.contains("AI access is off") == true, text ?? "nil")
    }
}
