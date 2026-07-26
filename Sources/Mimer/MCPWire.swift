import Foundation

/// The tiny request/response protocol spoken between the `mimer-mcp` server and the
/// running Mimer app over a local Mach port (CFMessagePort). Shared verbatim by both
/// targets so they can never drift. Pure Foundation; carries plaintext clip fields only
/// in memory, over a local-machine-only port the app opens **only when the user opts in**.
enum MCPWire {
    /// Local CFMessagePort name. Local ports are per-user and never network-reachable.
    static let portName = "com.hasanjafri.Mimer.mcp"

    /// Bump if the wire shape changes so an old server talking to a new app fails loudly.
    static let version = 1

    struct Request: Codable {
        enum Op: String, Codable { case recent, search }
        var version: Int = MCPWire.version
        var op: Op
        var query: String?     // for .search
        var limit: Int
    }

    struct Clip: Codable {
        var text: String
        var kind: String       // ClipKind name, e.g. "code", "link"
        var createdAt: Double  // epoch seconds
        var sourceApp: String?
        var isFavorite: Bool
    }

    struct Response: Codable {
        var version: Int = MCPWire.version
        var clips: [Clip]
    }

    static func encode<T: Encodable>(_ value: T) -> Data { (try? JSONEncoder().encode(value)) ?? Data() }
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? { try? JSONDecoder().decode(type, from: data) }
}
