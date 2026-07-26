import Foundation

// `mimer-mcp` — a Model Context Protocol server (JSON-RPC 2.0 over stdio) that lets a
// local AI client (Claude Desktop / Claude Code) use Mimer.
//
// Two kinds of tools:
//   • transform / list_transforms — stateless, run Mimer's ⌘K transform engine
//     (shared ClipTransform.swift). No history, no running app needed.
//   • recent_clips / search_clips — read clip history from the RUNNING app over a local
//     Mach port, which the app opens ONLY when the user turns on AI access (default off).
//     If that's off (or the app isn't running) these return a friendly note, never data.
//
// Everything lives in the `MCPServer` namespace so members are nonisolated statics; the
// stdio loop at the bottom is the only top-level (main-actor) code.

enum MCPServer {
    static let serverName = "mimer"
    static let serverVersion = "0.2.2"
    static let protocolVersion = "2024-11-05"

    // MARK: App IPC (history tools)

    static func queryApp(_ request: MCPWire.Request) -> MCPWire.Response? {
        guard let remote = CFMessagePortCreateRemote(nil, MCPWire.portName as CFString) else {
            return nil   // port absent → app not running, or AI access is off
        }
        defer { CFMessagePortInvalidate(remote) }
        let payload = MCPWire.encode(request) as CFData
        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(remote, 0, payload, 2.0, 2.0,
                                              CFRunLoopMode.defaultMode.rawValue, &reply)
        guard status == Int32(kCFMessagePortSuccess),
              let data = reply?.takeRetainedValue() as Data? else { return nil }
        return MCPWire.decode(MCPWire.Response.self, from: data)
    }

    static let accessOffNote = """
    No clips available. Mimer isn't running, or local AI access is off. Turn it on in \
    Mimer → Settings → Privacy → “Allow local AI tools to read clips”, then try again.
    """

    static func format(_ clips: [MCPWire.Clip]) -> String {
        guard !clips.isEmpty else { return "No matching clips." }
        let lines = clips.enumerated().map { i, c -> String in
            var tags = [c.kind]
            if let app = c.sourceApp { tags.append(app) }
            if c.isFavorite { tags.append("★") }
            return "[\(i + 1)] (\(tags.joined(separator: " · ")))\n\(c.text)"
        }
        return "\(clips.count) clip(s):\n\n" + lines.joined(separator: "\n\n")
    }

    // MARK: Tools

    // Computed (not stored) so the non-Sendable [[String: Any]] isn't shared mutable
    // static state — strict-concurrency clean. Only read on tools/list, so cheap.
    static var toolDefinitions: [[String: Any]] { [
        [
            "name": "list_transforms",
            "description": "List the text transforms Mimer can run (JSON→TypeScript, decode JWT, slugify, Base64, etc.).",
            "inputSchema": ["type": "object", "properties": [:]],
        ],
        [
            "name": "transform",
            "description": "Run one of Mimer's text transforms on some text. Use list_transforms to see names. Stateless; no clipboard access.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Transform name, e.g. json-to-ts, decode-jwt, slugify, base64-decode."],
                    "text": ["type": "string", "description": "The text to transform."],
                ],
                "required": ["name", "text"],
            ],
        ],
        [
            "name": "recent_clips",
            "description": "Get the user's most recent clipboard entries from Mimer. Requires the user to have enabled AI access in Mimer (off by default).",
            "inputSchema": [
                "type": "object",
                "properties": ["limit": ["type": "integer", "description": "How many recent clips (default 20, max 100)."]],
            ],
        ],
        [
            "name": "search_clips",
            "description": "Search the user's Mimer clipboard history. Supports Mimer's filters (type:, app:, is:fav, /regex/) plus fuzzy text. Requires AI access enabled in Mimer (off by default).",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Search query, e.g. 'type:code auth' or 'app:slack'."],
                    "limit": ["type": "integer", "description": "Max results (default 20, max 100)."],
                ],
                "required": ["query"],
            ],
        ],
    ] }

    /// Runs a tool call. Returns (text, isError).
    static func callTool(_ name: String, _ args: [String: Any]) -> (String, Bool) {
        switch name {
        case "list_transforms":
            let list = ClipTransform.all.map { "\(ClipTransform.displayName(for: $0)) — \($0.name)" }.joined(separator: "\n")
            return (list, false)

        case "transform":
            guard let tName = args["name"] as? String, let text = args["text"] as? String else {
                return ("transform requires 'name' and 'text'.", true)
            }
            guard let t = ClipTransform.named(tName) else {
                return ("Unknown transform '\(tName)'. Use list_transforms to see the options.", true)
            }
            guard let out = t.apply(text), !out.isEmpty else {
                return ("Transform '\(tName)' did not apply to that input.", true)
            }
            return (out, false)

        case "recent_clips":
            let limit = (args["limit"] as? Int) ?? 20
            guard let resp = queryApp(MCPWire.Request(op: .recent, query: nil, limit: limit)) else {
                return (accessOffNote, false)
            }
            return (format(resp.clips), false)

        case "search_clips":
            guard let query = args["query"] as? String, !query.isEmpty else {
                return ("search_clips requires a 'query'.", true)
            }
            let limit = (args["limit"] as? Int) ?? 20
            guard let resp = queryApp(MCPWire.Request(op: .search, query: query, limit: limit)) else {
                return (accessOffNote, false)
            }
            return (format(resp.clips), false)

        default:
            return ("Unknown tool '\(name)'.", true)
        }
    }

    // MARK: JSON-RPC

    /// Returns a response object, or nil for notifications (no id → no reply).
    static func handle(_ msg: [String: Any]) -> [String: Any]? {
        let method = msg["method"] as? String ?? ""
        let id = msg["id"]   // absent for notifications

        func result(_ value: Any) -> [String: Any]? {
            guard let id else { return nil }
            return ["jsonrpc": "2.0", "id": id, "result": value]
        }
        func error(_ code: Int, _ message: String) -> [String: Any]? {
            guard let id else { return nil }
            return ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
        }

        switch method {
        case "initialize":
            return result([
                "protocolVersion": protocolVersion,
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": serverName, "version": serverVersion],
            ])
        case "notifications/initialized", "notifications/cancelled":
            return nil
        case "ping":
            return result([:] as [String: Any])
        case "tools/list":
            return result(["tools": toolDefinitions])
        case "tools/call":
            let params = msg["params"] as? [String: Any] ?? [:]
            guard let name = params["name"] as? String else { return error(-32602, "Missing tool name") }
            let args = params["arguments"] as? [String: Any] ?? [:]
            let (text, isError) = callTool(name, args)
            return result([
                "content": [["type": "text", "text": text]],
                "isError": isError,
            ])
        default:
            return error(-32601, "Method not found: \(method)")
        }
    }

    static func emit(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []) else { return }
        let out = FileHandle.standardOutput
        out.write(data)
        out.write(Data([0x0a]))   // newline delimiter
    }
}

// MARK: - stdio loop (newline-delimited JSON-RPC)

while let line = readLine(strippingNewline: true) {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
          let msg = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { continue }
    if let response = MCPServer.handle(msg) { MCPServer.emit(response) }
}
