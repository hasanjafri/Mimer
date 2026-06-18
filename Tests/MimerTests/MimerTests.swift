import XCTest
import AppKit
@testable import Mimer

final class ClipboardMonitorTests: XCTestCase {
    /// Each test gets an isolated, uniquely-named pasteboard so we never touch the
    /// user's real clipboard.
    private func makeMonitor(maxItems: Int = 50) -> (ClipboardMonitor, NSPasteboard) {
        let pb = NSPasteboard(name: NSPasteboard.Name("MimerTest-\(UUID().uuidString)"))
        pb.clearContents()
        return (ClipboardMonitor(pasteboard: pb, maxItems: maxItems), pb)
    }

    func testCapturesAndDeduplicates() {
        let (m, pb) = makeMonitor()
        pb.clearContents(); pb.setString("alpha", forType: .string)
        XCTAssertTrue(m.captureIfChanged())
        XCTAssertEqual(m.clips, ["alpha"])

        pb.clearContents(); pb.setString("beta", forType: .string)
        XCTAssertTrue(m.captureIfChanged())
        XCTAssertEqual(m.clips, ["beta", "alpha"])

        // Re-copying an existing clip moves it to the top without duplicating.
        pb.clearContents(); pb.setString("alpha", forType: .string)
        XCTAssertTrue(m.captureIfChanged())
        XCTAssertEqual(m.clips, ["alpha", "beta"])
    }

    func testIgnoresConcealedType() {
        let (m, pb) = makeMonitor()
        pb.clearContents()
        pb.declareTypes(
            [.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")],
            owner: nil
        )
        pb.setString("hunter2", forType: .string)
        XCTAssertFalse(m.captureIfChanged())     // password-manager copy → skipped
        XCTAssertTrue(m.clips.isEmpty)
    }

    func testRespectsMaxItems() {
        let (m, pb) = makeMonitor(maxItems: 3)
        for s in ["a", "b", "c", "d"] {
            pb.clearContents(); pb.setString(s, forType: .string)
            m.captureIfChanged()
        }
        XCTAssertEqual(m.clips, ["d", "c", "b"])  // oldest ("a") pruned
    }

    func testNoCaptureWhenUnchanged() {
        let (m, pb) = makeMonitor()
        pb.clearContents(); pb.setString("x", forType: .string)
        XCTAssertTrue(m.captureIfChanged())
        XCTAssertFalse(m.captureIfChanged())      // changeCount unchanged → no-op
    }

    func testIgnoresEmptyAndWhitespace() {
        let (m, pb) = makeMonitor()
        pb.clearContents(); pb.setString("   \n ", forType: .string)
        XCTAssertFalse(m.captureIfChanged())
        XCTAssertTrue(m.clips.isEmpty)
    }
}
