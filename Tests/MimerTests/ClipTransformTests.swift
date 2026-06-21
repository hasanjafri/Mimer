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

    func testDecodeJWT() {
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
            + ".eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ"
            + ".SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        let out = transform("jwt").apply(jwt)
        XCTAssertNotNil(out)
        XCTAssertTrue(out!.contains("\"alg\" : \"HS256\""))   // header decoded
        XCTAssertTrue(out!.contains("\"name\" : \"John Doe\""))  // payload decoded
        XCTAssertTrue(out!.contains("// payload"))
        XCTAssertNil(transform("jwt").apply("a.b.c"))         // dotted prose is not a JWT
        XCTAssertNil(transform("jwt").apply("not a jwt"))
        XCTAssertNil(transform("jwt").apply("W10.W10.sig"))   // segments decode to JSON arrays ([]), not objects
    }

    func testStripTrackingParams() {
        XCTAssertEqual(transform("urlstrip").apply("https://example.com/p?utm_source=x&id=5&fbclid=abc"),
                       "https://example.com/p?id=5")
        XCTAssertEqual(transform("urlstrip").apply("https://example.com/p?utm_campaign=a&utm_medium=b"),
                       "https://example.com/p")                 // all params stripped → no query
        XCTAssertNil(transform("urlstrip").apply("https://example.com/p?id=5"))   // nothing to strip → hidden
        XCTAssertNil(transform("urlstrip").apply("just text"))
        XCTAssertNil(transform("urlstrip").apply("httpx://example.com/p?utm_source=x"))  // not a real http(s) scheme
    }

    func testDecodeQueryString() {
        XCTAssertEqual(transform("urlquery").apply("https://example.com/p?a=1&b=two"), "a = 1\nb = two")
        XCTAssertNil(transform("urlquery").apply("https://example.com/p"))   // no query → hidden
        XCTAssertNil(transform("urlquery").apply("foo?bar=baz"))             // bare non-URL → hidden (not clutter)
    }

    func testTimestampConversions() {
        XCTAssertEqual(transform("epoch2iso").apply("1516239022"), "2018-01-18T01:30:22Z")
        XCTAssertEqual(transform("epoch2iso").apply("1516239022000"), "2018-01-18T01:30:22Z")  // millis
        XCTAssertEqual(transform("epoch2iso").apply("946684800"), "2000-01-01T00:00:00Z")       // 9-digit seconds
        XCTAssertNil(transform("epoch2iso").apply("12345"))         // too few digits
        XCTAssertNil(transform("epoch2iso").apply("not a number"))
        XCTAssertEqual(transform("iso2epoch").apply("2018-01-18T01:30:22Z"), "1516239022")
        XCTAssertEqual(transform("iso2epoch").apply("2018-01-18T01:30:22.123Z"), "1516239022")  // fractional seconds
        XCTAssertNil(transform("iso2epoch").apply("not a date"))
    }
}
