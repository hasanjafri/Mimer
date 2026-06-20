import XCTest
@testable import Mimer

final class ClipTransformTests: XCTestCase {
    private func transform(_ id: String) -> ClipTransform {
        ClipTransform.all.first { $0.id == id }!
    }

    func testBase64RoundTrip() {
        XCTAssertEqual(transform("b64enc").apply("Hello"), "SGVsbG8=")
        XCTAssertEqual(transform("b64dec").apply("SGVsbG8="), "Hello")
        XCTAssertNil(transform("b64dec").apply("not valid base64 !!!"))
        XCTAssertNil(transform("b64dec").apply("test"))   // short word → not offered as base64
    }

    func testTitleCase() {
        XCTAssertEqual(transform("title").apply("hello world"), "Hello World")
        XCTAssertEqual(transform("title").apply("don't stop"), "Don't Stop")   // not "Don'T Stop"
    }

    func testURLEncoding() {
        XCTAssertEqual(transform("urlenc").apply("a b&c"), "a%20b%26c")
        XCTAssertEqual(transform("urldec").apply("a%20b%26c"), "a b&c")
    }

    func testJSONPrettyAndMinify() {
        let pretty = transform("jsonpretty").apply("{\"b\":1,\"a\":2}")
        XCTAssertNotNil(pretty)
        XCTAssertTrue(pretty!.contains("\n"))            // multi-line
        XCTAssertTrue(pretty!.range(of: "\"a\"")!.lowerBound < pretty!.range(of: "\"b\"")!.lowerBound) // sorted keys
        XCTAssertEqual(transform("jsonmin").apply("{ \"a\" : 1 }"), "{\"a\":1}")
        XCTAssertNil(transform("jsonpretty").apply("just prose, not json"))
    }

    func testSlugify() {
        XCTAssertEqual(transform("slug").apply("Hello, World! Foo"), "hello-world-foo")
    }

    func testApplicableHidesNoOpsAndOffersRealOnes() {
        let applicable = ClipTransform.applicable(to: "HELLO")
        XCTAssertFalse(applicable.contains { $0.id == "upper" })   // already uppercase → no-op hidden
        XCTAssertTrue(applicable.contains { $0.id == "lower" })
        XCTAssertTrue(ClipTransform.applicable(to: "{\"x\":1}").contains { $0.id == "jsonpretty" })
    }
}
