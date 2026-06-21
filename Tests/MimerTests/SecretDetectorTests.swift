import XCTest
@testable import Mimer

final class SecretDetectorTests: XCTestCase {
    // Synthetic secrets are built from parts at runtime so no full secret-shaped literal
    // is committed (GitHub's secret-scanning push protection flags real-looking literals,
    // even in tests). These still match SecretDetector's patterns.
    private let aws = "AKIA" + "0123456789ABCDEF"                       // AKIA + 16
    private let openAI = "sk-" + String(repeating: "a", count: 40)
    private let github = "ghp_" + String(repeating: "b", count: 36)
    private let slack = "xoxb-" + String(repeating: "c", count: 24)
    private let google = "AIza" + String(repeating: "d", count: 35)    // 39 total
    private let pem = ["-----BEGIN RSA ", "PRIVATE KEY-----", "\nMIIabc...\n", "-----END RSA ", "PRIVATE KEY-----"].joined()
    private let envSecret = "export AWS_SECRET_ACCESS_" + "KEY=" + String(repeating: "z", count: 20)

    func testDetectsKnownSecretShapes() {
        XCTAssertEqual(SecretDetector.kind(of: aws), "AWS key")
        XCTAssertEqual(SecretDetector.kind(of: openAI), "API key")
        XCTAssertEqual(SecretDetector.kind(of: github), "GitHub token")
        XCTAssertEqual(SecretDetector.kind(of: slack), "Slack token")
        XCTAssertEqual(SecretDetector.kind(of: google), "Google API key")
        XCTAssertEqual(SecretDetector.kind(of: pem), "Private key")
        XCTAssertEqual(SecretDetector.kind(of: envSecret), "Secret")
        XCTAssertEqual(SecretDetector.kind(of: "API_" + "TOKEN=abcdef123456"), "Secret")
        XCTAssertEqual(SecretDetector.kind(of: "api_" + "key=abcdef123456"), "Secret")   // lowercase dotenv
        XCTAssertEqual(SecretDetector.kind(of: "password=hunter2hunter"), "Secret")
    }

    func testIgnoresOrdinaryClips() {
        XCTAssertNil(SecretDetector.kind(of: "hello world"))
        XCTAssertNil(SecretDetector.kind(of: "https://example.com/path?utm_source=x"))
        XCTAssertNil(SecretDetector.kind(of: "{\"a\":1,\"b\":2}"))
        XCTAssertNil(SecretDetector.kind(of: "this is my secret recipe"))   // prose with "secret"
        XCTAssertNil(SecretDetector.kind(of: "sk-1"))                       // too short to be a key
        XCTAssertNil(SecretDetector.kind(of: "PORT=8080"))                  // not a secret-named var
        XCTAssertNil(SecretDetector.kind(of: "monkey=banana123456"))        // "key" is a substring, not a component
        XCTAssertNil(SecretDetector.kind(of: "SECRET_SANTA=bob"))           // value too short
        XCTAssertNil(SecretDetector.kind(of: "eyJhbGciOiJIUzI1NiJ9.e30.x")) // JWT — decoded, not masked
    }

    func testMaskedPreviewHidesTheMiddleButStaysIdentifiable() {
        XCTAssertEqual(SecretDetector.maskedPreview(aws), "AWS key ••••CDEF")
        XCTAssertEqual(SecretDetector.maskedPreview(pem), "Private key ••••")  // multi-line → bare label
        XCTAssertNil(SecretDetector.maskedPreview("hello world"))
    }
}
