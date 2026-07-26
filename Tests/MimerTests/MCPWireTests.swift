import XCTest
@testable import Mimer

final class MCPWireTests: XCTestCase {
    func testRequestRoundTrip() {
        let req = MCPWire.Request(op: .search, query: "type:code auth", limit: 15)
        let decoded = MCPWire.decode(MCPWire.Request.self, from: MCPWire.encode(req))
        XCTAssertEqual(decoded?.op, .search)
        XCTAssertEqual(decoded?.query, "type:code auth")
        XCTAssertEqual(decoded?.limit, 15)
        XCTAssertEqual(decoded?.version, MCPWire.version)
    }

    func testResponseRoundTrip() {
        let clip = MCPWire.Clip(text: "hi", kind: "code", createdAt: 123, sourceApp: "Terminal", isFavorite: true)
        let decoded = MCPWire.decode(MCPWire.Response.self, from: MCPWire.encode(MCPWire.Response(clips: [clip])))
        XCTAssertEqual(decoded?.clips.count, 1)
        XCTAssertEqual(decoded?.clips.first?.text, "hi")
        XCTAssertEqual(decoded?.clips.first?.isFavorite, true)
    }

    func testDecodeGarbageIsNil() {
        XCTAssertNil(MCPWire.decode(MCPWire.Request.self, from: Data("not json".utf8)))
    }
}
