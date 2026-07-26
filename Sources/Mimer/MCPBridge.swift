import Foundation
import Combine

/// App-side half of the MCP integration. When — and only when — the user opts in
/// (`Preferences.mcpEnabled`, default off), this registers a **local** Mach port that
/// the `mimer-mcp` server queries for clip history. While off, no port is registered,
/// so an MCP client can read nothing: the default-off gate is enforced here, in the app,
/// not by the server's good behavior.
///
/// The port is local (per-user, never network-reachable). Clips are read from the
/// already-decrypted in-memory `ClipStore` — nothing new is written to disk — and detected
/// secrets are masked in the output when masking is on, exactly as in the UI.
@MainActor
final class MCPBridge {
    static let shared = MCPBridge()

    private var port: CFMessagePort?
    private var runLoopSource: CFRunLoopSource?
    private var cancellable: AnyCancellable?

    private init() {}

    /// Call once at launch: reflect the current preference and track changes to it.
    func activate() {
        apply(Preferences.shared.mcpEnabled)
        cancellable = Preferences.shared.$mcpEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in self?.apply(enabled) }
    }

    private func apply(_ enabled: Bool) { enabled ? start() : stop() }

    private func start() {
        guard port == nil else { return }
        guard let p = CFMessagePortCreateLocal(nil, MCPWire.portName as CFString, mcpPortCallback, nil, nil) else {
            return   // name already taken (another instance) — stay silent, expose nothing
        }
        let source = CFMessagePortCreateRunLoopSource(nil, p, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        port = p
        runLoopSource = source
    }

    private func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let p = port { CFMessagePortInvalidate(p); port = nil }
    }

    /// Answer one request off the live app state. Thin wrapper over the pure `respond`.
    func handle(_ data: Data) -> Data {
        guard let req = MCPWire.decode(MCPWire.Request.self, from: data) else {
            return MCPWire.encode(MCPWire.Response(clips: []))
        }
        let resp = Self.respond(to: req, items: ClipStore.shared.items,
                                maskSecrets: Preferences.shared.maskSecrets,
                                enabled: Preferences.shared.mcpEnabled)
        return MCPWire.encode(resp)
    }

    /// Pure core (no port, no app, no Core Data) so the gate is exhaustively testable.
    /// Returns nothing unless `enabled` — the default-off gate — and the wire version matches;
    /// filters out image clips, honors `maskSecrets`, and caps the result at 100.
    nonisolated static func respond(to request: MCPWire.Request, items: [ClipItem],
                                    maskSecrets: Bool, enabled: Bool) -> MCPWire.Response {
        guard enabled, request.version == MCPWire.version else { return MCPWire.Response(clips: []) }
        let limit = max(1, min(request.limit, 100))
        let textItems = items.filter { $0.kind != .image }   // text clips only
        let selected: [ClipItem]
        switch request.op {
        case .recent:
            selected = Array(textItems.prefix(limit))
        case .search:
            let q = SearchQuery.parse(request.query ?? "")
            selected = Array(textItems.filter { q.matches($0) }.prefix(limit))
        }
        let clips = selected.map { item -> MCPWire.Clip in
            let text = (maskSecrets ? SecretDetector.maskedPreview(item.text) : nil) ?? item.text
            return MCPWire.Clip(text: text, kind: kindName(item.kind),
                                createdAt: item.createdAt.timeIntervalSince1970,
                                sourceApp: item.sourceApp, isFavorite: item.isFavorite)
        }
        return MCPWire.Response(clips: clips)
    }
}

private func kindName(_ kind: ClipKind) -> String {
    switch kind {
    case .text: return "text"
    case .code: return "code"
    case .link: return "link"
    case .color: return "color"
    case .image: return "image"
    case .file: return "file"
    case .snippet: return "snippet"
    case .gitSHA: return "sha"
    case .issueKey: return "issue"
    case .fileRef: return "file-ref"
    }
}

/// CFMessagePort local callback. Runs on the main run loop (the source is added there),
/// so hopping onto the main actor with `assumeIsolated` is valid — same pattern the Timer
/// callbacks use. Non-capturing, so it converts to the required C function pointer.
private func mcpPortCallback(_ port: CFMessagePort?, _ msgid: Int32,
                             _ data: CFData?, _ info: UnsafeMutableRawPointer?) -> Unmanaged<CFData>? {
    let request = (data as Data?) ?? Data()
    let reply = MainActor.assumeIsolated { MCPBridge.shared.handle(request) }
    return Unmanaged.passRetained(reply as CFData)
}
