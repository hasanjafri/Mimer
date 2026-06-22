import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// In-memory thumbnail cache for image clips, keyed by blob hash. Decrypts the blob (via
/// `ClipStore.blobData`) and downsamples once with ImageIO, then serves from the cache so list
/// rows don't decrypt/decode per render.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    func thumbnail(for hash: String, maxPixel: CGFloat = 64) -> NSImage? {
        let key = "\(hash)@\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = ClipStore.shared.blobData(hash),
              let image = Self.downsample(data, maxPixel: maxPixel) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    private static func downsample(_ data: Data, maxPixel: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

/// A small rounded thumbnail for an image clip — falls back to the photo glyph if the blob is
/// missing/unreadable (e.g. lost encryption key).
struct ClipThumbnail: View {
    let hash: String?
    var size: CGFloat = 26

    var body: some View {
        Group {
            if let hash, let image = ThumbnailCache.shared.thumbnail(for: hash) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary.opacity(0.25)))
            } else {
                Image(systemName: "photo").foregroundStyle(.teal).frame(width: size, height: size)
            }
        }
    }
}
