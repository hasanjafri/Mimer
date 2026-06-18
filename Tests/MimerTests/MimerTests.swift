import XCTest
@testable import Mimer

final class MimerTests: XCTestCase {
    /// Bootstrap: proves the app target is testable and the test scheme runs.
    /// Real coverage (capture/ignore rules, dedup, pruning-exempts-favorites,
    /// pasteboard-race, CloudKit schema validity) arrives with Phase 1.
    func testScaffoldIsTestable() {
        XCTAssertTrue(true)
    }
}
