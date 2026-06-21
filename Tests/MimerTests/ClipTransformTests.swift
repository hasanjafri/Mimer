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

    func testJSONToTypeScript() {
        let out = transform("json2ts").apply("{\"name\":\"Bob\",\"age\":30,\"admin\":true,\"tags\":[\"a\"],\"meta\":{\"x\":1}}")
        XCTAssertNotNil(out)
        XCTAssertTrue(out!.hasPrefix("interface Root {"))
        XCTAssertTrue(out!.contains("name: string;"))
        XCTAssertTrue(out!.contains("age: number;"))
        XCTAssertTrue(out!.contains("admin: boolean;"))   // bool not number
        XCTAssertTrue(out!.contains("tags: string[];"))
        XCTAssertTrue(out!.contains("meta: {"))           // nested object inlined
        XCTAssertNil(transform("json2ts").apply("[1,2,3]"))        // top-level array → not an interface
        XCTAssertNil(transform("json2ts").apply("just prose"))
    }

    func testJSONToTypeScriptEdgeCases() {
        // Heterogeneous array → union, not just the first element's type.
        XCTAssertTrue(transform("json2ts").apply("{\"x\":[1,\"a\"]}")!.contains("x: (number | string)[];"))
        XCTAssertTrue(transform("json2ts").apply("{\"x\":[]}")!.contains("x: any[];"))
        // Non-identifier key is escaped, not emitted raw.
        let escaped = transform("json2ts").apply("{\"a\\\"b\":1}")!
        XCTAssertTrue(escaped.contains("\"a\\\"b\": number;"))
        XCTAssertFalse(escaped.contains("\"a\"b\""))   // not the broken/unescaped form
    }

    func testLineOps() {
        XCTAssertEqual(transform("sortlines").apply("banana\napple\ncherry"), "apple\nbanana\ncherry")
        XCTAssertEqual(transform("dedupelines").apply("a\nb\na\nc\nb"), "a\nb\nc")
        XCTAssertEqual(transform("reverselines").apply("1\n2\n3"), "3\n2\n1")
        XCTAssertNil(transform("sortlines").apply("single line"))           // single line → hidden
        XCTAssertNil(transform("reverselines").apply("single line"))
        XCTAssertNil(transform("sortlines").apply("single line\n"))         // trailing newline ≠ a second line
        XCTAssertEqual(transform("sortlines").apply("b\na\n"), "a\nb\n")    // trailing newline preserved
        // dedupe with no duplicates is hidden by applicable() (output == input)
        XCTAssertFalse(ClipTransform.applicable(to: "a\nb\nc").contains { $0.id == "dedupelines" })
        XCTAssertTrue(ClipTransform.applicable(to: "a\nb\na").contains { $0.id == "dedupelines" })
    }

    func testCaseConversions() {
        XCTAssertEqual(transform("camel").apply("user name"), "userName")
        XCTAssertEqual(transform("camel").apply("user_profile_id"), "userProfileId")
        XCTAssertEqual(transform("snake").apply("userName"), "user_name")          // camelCase boundary split
        XCTAssertEqual(transform("snake").apply("User Profile ID"), "user_profile_id")
        XCTAssertEqual(transform("snake").apply("parseURLValue"), "parse_url_value")  // acronym boundary
        XCTAssertNil(transform("camel").apply("This is just prose"))                // 4-word prose, no signal → hidden
        XCTAssertNil(transform("camel").apply("a full sentence, with punctuation.")) // punctuation → hidden
        XCTAssertNil(transform("snake").apply("multi\nline"))                       // not a single identifier-ish line
    }
}
