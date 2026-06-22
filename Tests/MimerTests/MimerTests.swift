import XCTest
import AppKit
@testable import Mimer

@MainActor
final class ClipboardMonitorTests: XCTestCase {
    /// Isolated, uniquely-named pasteboard + a capture sink that records forwarded text.
    private func makeMonitor() -> (ClipboardMonitor, NSPasteboard, () -> [String]) {
        let pb = NSPasteboard(name: NSPasteboard.Name("MimerTest-\(UUID().uuidString)"))
        pb.clearContents()
        var captured: [String] = []
        let monitor = ClipboardMonitor(pasteboard: pb, onCapture: { captured.append($0) })
        return (monitor, pb, { captured })
    }

    /// A tiny valid PNG (1×1) for image-capture tests.
    private func pngData() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32)!
        return rep.representation(using: .png, properties: [:])!
    }

    func testCapturesImageWhenNoText() {
        let pb = NSPasteboard(name: NSPasteboard.Name("MimerTestImg-\(UUID().uuidString)"))
        pb.clearContents()
        var texts: [String] = []; var images: [Data] = []
        let m = ClipboardMonitor(pasteboard: pb, onCapture: { texts.append($0) }, onCaptureImage: { images.append($0) })
        let png = pngData()
        pb.clearContents(); pb.setData(png, forType: .png)
        XCTAssertTrue(m.captureIfChanged())
        XCTAssertEqual(images.count, 1)          // image forwarded
        XCTAssertTrue(texts.isEmpty)
    }

    func testPrefersTextOverImage() {
        let pb = NSPasteboard(name: NSPasteboard.Name("MimerTestImg-\(UUID().uuidString)"))
        pb.clearContents()
        var texts: [String] = []; var images: [Data] = []
        let m = ClipboardMonitor(pasteboard: pb, onCapture: { texts.append($0) }, onCaptureImage: { images.append($0) })
        pb.clearContents()
        pb.declareTypes([.string, .png], owner: nil)
        pb.setString("caption", forType: .string)
        pb.setData(pngData(), forType: .png)
        XCTAssertTrue(m.captureIfChanged())
        XCTAssertEqual(texts, ["caption"])       // text wins when both present
        XCTAssertTrue(images.isEmpty)
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
