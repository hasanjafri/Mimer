import XCTest
import AppKit
@testable import Mimer

final class ClipboardMonitorTests: XCTestCase {
    /// Isolated, uniquely-named pasteboard + a capture sink that records forwarded text.
    private func makeMonitor() -> (ClipboardMonitor, NSPasteboard, () -> [String]) {
        let pb = NSPasteboard(name: NSPasteboard.Name("MimerTest-\(UUID().uuidString)"))
        pb.clearContents()
        var captured: [String] = []
        let monitor = ClipboardMonitor(pasteboard: pb, onCapture: { captured.append($0) })
        return (monitor, pb, { captured })
    }

    func testForwardsCapturedText() {
        let (m, pb, captured) = makeMonitor()
        pb.clearContents(); pb.setString("alpha", forType: .string)
        XCTAssertTrue(m.captureIfChanged())
        XCTAssertEqual(captured(), ["alpha"])
    }

    func testIgnoresConcealedType() {
        let (m, pb, captured) = makeMonitor()
        pb.clearContents()
        pb.declareTypes(
            [.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")],
            owner: nil
        )
        pb.setString("hunter2", forType: .string)
        XCTAssertFalse(m.captureIfChanged())     // password-manager copy → skipped
        XCTAssertTrue(captured().isEmpty)
    }

    func testIgnoresEmptyAndWhitespace() {
        let (m, pb, captured) = makeMonitor()
        pb.clearContents(); pb.setString("   \n ", forType: .string)
        XCTAssertFalse(m.captureIfChanged())
        XCTAssertTrue(captured().isEmpty)
    }

    func testNoCaptureWhenUnchanged() {
        let (m, pb, captured) = makeMonitor()
        pb.clearContents(); pb.setString("x", forType: .string)
        XCTAssertTrue(m.captureIfChanged())
        XCTAssertFalse(m.captureIfChanged())     // changeCount unchanged → no-op
        XCTAssertEqual(captured(), ["x"])
    }

    func testIgnoresRestoredType() {
        let (m, pb, captured) = makeMonitor()
        pb.clearContents()
        pb.declareTypes(
            [.string, NSPasteboard.PasteboardType("org.nspasteboard.RestoredType")],
            owner: nil
        )
        pb.setString("our own paste-back", forType: .string)
        XCTAssertFalse(m.captureIfChanged())     // self-paste marker → skipped
        XCTAssertTrue(captured().isEmpty)
    }

    func testRespectsShouldCaptureGate() {
        let pb = NSPasteboard(name: NSPasteboard.Name("MimerTest-\(UUID().uuidString)"))
        pb.clearContents()
        var captured: [String] = []
        let monitor = ClipboardMonitor(pasteboard: pb, shouldCapture: { false }, onCapture: { captured.append($0) })
        pb.clearContents(); pb.setString("blocked while paused/excluded", forType: .string)
        XCTAssertFalse(monitor.captureIfChanged())
        XCTAssertTrue(captured.isEmpty)
    }
}
