import XCTest
import CryptoKit
@testable import Mimer

final class CryptorTests: XCTestCase {
    private let cryptor = Cryptor(key: SymmetricKey(data: Data(repeating: 3, count: 32)))

    func testRoundTrips() {
        for s in ["hello", "", "ghp_secret_token_value", "multi\nline\nclip", "🔐 unicode ✓"] {
            guard let enc = cryptor.encrypt(s) else { XCTFail("encrypt returned nil for \(s)"); continue }
            XCTAssertTrue(enc.hasPrefix(Cryptor.prefix), "should be marked encrypted")
            if !s.isEmpty { XCTAssertFalse(enc.contains(s), "plaintext must not appear in ciphertext") }
            XCTAssertEqual(cryptor.decrypt(enc), s)
        }
    }

    func testEncryptionIsNondeterministic() {
        // Random nonce → same plaintext encrypts to different ciphertext each time.
        XCTAssertNotEqual(cryptor.encrypt("same"), cryptor.encrypt("same"))
    }

    func testLegacyPlaintextPassesThrough() {
        XCTAssertEqual(cryptor.decrypt("plain legacy value"), "plain legacy value")
        XCTAssertFalse(cryptor.isEncrypted("plain legacy value"))
    }

    func testWrongKeyOrCorruptReturnsNil() {
        let enc = cryptor.encrypt("secret")!
        let other = Cryptor(key: SymmetricKey(data: Data(repeating: 4, count: 32)))
        XCTAssertNil(other.decrypt(enc), "a different key must not decrypt")
        XCTAssertNil(cryptor.decrypt(Cryptor.prefix + "not-valid-base64!!"), "corrupt payload → nil")
        XCTAssertNil(cryptor.decrypt(Cryptor.prefix + Data("garbage".utf8).base64EncodedString()))
    }

    func testDedupeHashIsDeterministicKeyedAndDistinct() {
        XCTAssertEqual(cryptor.dedupeHash("abc"), cryptor.dedupeHash("abc"))   // deterministic
        XCTAssertNotEqual(cryptor.dedupeHash("abc"), cryptor.dedupeHash("abd"))  // distinct inputs
        let other = Cryptor(key: SymmetricKey(data: Data(repeating: 4, count: 32)))
        XCTAssertNotEqual(cryptor.dedupeHash("abc"), other.dedupeHash("abc"))  // key-dependent
    }
}
