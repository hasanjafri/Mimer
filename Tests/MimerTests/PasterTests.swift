import XCTest
@testable import Mimer

final class PasterTests: XCTestCase {
    // The auto-paste target guard: only fire ⌘V into the exact app that was frontmost when the
    // palette opened, and only if it's still frontmost + alive. Anything else fails closed so a
    // clip (possibly a secret) never lands in an app that grabbed focus during the paste delay.

    func testPastesWhenTargetStillFrontmost() {
        XCTAssertTrue(Paster.shouldAutoPaste(targetPID: 42, targetTerminated: false, frontmostPID: 42))
    }

    func testDoesNotPasteWhenFocusMoved() {
        XCTAssertFalse(Paster.shouldAutoPaste(targetPID: 42, targetTerminated: false, frontmostPID: 99))
    }

    func testDoesNotPasteWhenTargetTerminated() {
        XCTAssertFalse(Paster.shouldAutoPaste(targetPID: 42, targetTerminated: true, frontmostPID: 42))
    }

    func testDoesNotPasteWhenTargetUnknown() {
        XCTAssertFalse(Paster.shouldAutoPaste(targetPID: nil, targetTerminated: false, frontmostPID: 42))
        XCTAssertFalse(Paster.shouldAutoPaste(targetPID: nil, targetTerminated: true, frontmostPID: nil))
    }

    func testDoesNotPasteWhenNothingFrontmost() {
        XCTAssertFalse(Paster.shouldAutoPaste(targetPID: 42, targetTerminated: false, frontmostPID: nil))
    }
}
