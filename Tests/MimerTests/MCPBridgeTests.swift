import XCTest
@testable import Mimer

/// Unit tests for the MCP gate logic (`MCPBridge.respond`), the security-critical core.
/// Pure — no port, no app, no Core Data.
final class MCPBridgeTests: XCTestCase {
    private func item(_ text: String, _ kind: ClipKind = .text, fav: Bool = false, app: String? = nil) -> ClipItem {
        ClipItem(id: UUID(), text: text, kind: kind, createdAt: Date(), isFavorite: fav, sourceApp: app)
    }

    private func recent(_ items: [ClipItem], enabled: Bool, mask: Bool = false, limit: Int = 20) -> [MCPWire.Clip] {
        MCPBridge.respond(to: MCPWire.Request(op: .recent, query: nil, limit: limit),
                          items: items, maskSecrets: mask, enabled: enabled).clips
    }

    // The whole point of the feature: OFF means nothing leaks, even with clips present.
    func testDisabledReturnsNothing() {
        let clips = recent([item("secret plan"), item("another")], enabled: false)
        XCTAssertTrue(clips.isEmpty)
    }

    func testEnabledReturnsRecentTextClips() {
        let clips = recent([item("one"), item("two")], enabled: true)
        XCTAssertEqual(clips.map(\.text), ["one", "two"])
    }

    func testImageClipsAreFilteredOut() {
        let clips = recent([item("text one"), item("", .image), item("text two")], enabled: true)
        XCTAssertEqual(clips.map(\.text), ["text one", "text two"])
    }

    func testLimitIsRespectedAndCapped() {
        let many = (0..<200).map { item("clip \($0)") }
        XCTAssertEqual(recent(many, enabled: true, limit: 5).count, 5)
        XCTAssertEqual(recent(many, enabled: true, limit: 10_000).count, 100)  // hard cap
    }

    func testSecretsExcludedFromRecentWhenMaskingOn() {
        let aws = "AKIA" + "0123456789ABCDEF"
        // Masking on: the secret clip is kept off the AI surface entirely, not masked.
        let masked = recent([item(aws), item("ordinary note")], enabled: true, mask: true)
        XCTAssertEqual(masked.map(\.text), ["ordinary note"])
        // Masking off: the user opted out of masking, so full text is exposed (UI parity).
        let unmasked = recent([item(aws)], enabled: true, mask: false)
        XCTAssertEqual(unmasked.first?.text, aws)
    }

    // Regression: search must not become an oracle. With masking on, a query that would match
    // a secret's raw content returns nothing, so hit/no-hit can't reconstruct the secret.
    func testSearchCannotOracleSecretsWhenMaskingOn() {
        let aws = "AKIA" + "0123456789ABCDEF"
        let items = [item(aws), item("public value")]
        let hit = MCPBridge.respond(to: MCPWire.Request(op: .search, query: "/AKIA0123/", limit: 20),
                                    items: items, maskSecrets: true, enabled: true).clips
        XCTAssertTrue(hit.isEmpty, "secret leaked through search: \(hit.map(\.text))")
        // type:secret must not enumerate secrets either.
        let enumerate = MCPBridge.respond(to: MCPWire.Request(op: .search, query: "type:secret", limit: 20),
                                          items: items, maskSecrets: true, enabled: true).clips
        XCTAssertTrue(enumerate.isEmpty)
    }

    func testSearchFiltersViaSearchQuery() {
        let items = [item("alpha auth token"), item("beta config"), item("gamma auth")]
        let clips = MCPBridge.respond(to: MCPWire.Request(op: .search, query: "auth", limit: 20),
                                      items: items, maskSecrets: false, enabled: true).clips
        XCTAssertEqual(Set(clips.map(\.text)), ["alpha auth token", "gamma auth"])
    }

    func testWireVersionMismatchReturnsNothing() {
        var req = MCPWire.Request(op: .recent, query: nil, limit: 20)
        req.version = MCPWire.version + 1
        let clips = MCPBridge.respond(to: req, items: [item("x")], maskSecrets: false, enabled: true).clips
        XCTAssertTrue(clips.isEmpty)
    }

    func testClipMetadataIsCarried() {
        let clips = recent([item("hi", .code, fav: true, app: "Terminal")], enabled: true)
        XCTAssertEqual(clips.first?.kind, "code")
        XCTAssertEqual(clips.first?.isFavorite, true)
        XCTAssertEqual(clips.first?.sourceApp, "Terminal")
    }
}
