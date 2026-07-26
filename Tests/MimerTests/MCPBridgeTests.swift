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

    func testSecretsAreMaskedWhenMaskingOn() {
        let aws = "AKIA" + "0123456789ABCDEF"
        let masked = recent([item(aws)], enabled: true, mask: true)
        XCTAssertEqual(masked.first?.text, "AWS key ••••CDEF")
        let unmasked = recent([item(aws)], enabled: true, mask: false)
        XCTAssertEqual(unmasked.first?.text, aws)
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
