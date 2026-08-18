import SwiftUI
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// What an image blob says about itself — shown in the hover preview card.
struct ImageBlobInfo: Sendable, Equatable {
    var pixelWidth: Int?
    var pixelHeight: Int?
    var byteCount: Int
    var type: String?      // "PNG", "TIFF", …
}

/// In-memory thumbnail cache for image clips, keyed by blob hash. Decrypts the blob (on the
/// main actor — a fast file read) then downsamples **off the main actor** via ImageIO, returning
/// a Sendable `CGImage`. Bounded so scrolling many images can't grow memory without limit.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()
    private var infos: [String: ImageBlobInfo] = [:]

    // The preview card asks for much larger thumbnails than a row does, so bound by bytes as
    // well as by count — 256 full-size previews would be hundreds of megabytes.
    init() {
        cache.countLimit = 256
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    func thumbnail(for hash: String, maxPixel: CGFloat = 64) async -> NSImage? {
        let key = "\(hash)@\(Int(maxPixel))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let data = ClipStore.shared.blobData(hash) else { return nil }   // decrypt (fast)
        guard let cg = await Task.detached(priority: .userInitiated, operation: {
            Self.downsample(data, maxPixel: maxPixel)            // ImageIO decode/resize off-main
        }).value else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: key, cost: cg.width * cg.height * 4)
        return image
    }

    /// Dimensions / encoding / size of the stored blob, read from the image headers only.
    func info(for hash: String) async -> ImageBlobInfo? {
        if let cached = infos[hash] { return cached }
        guard let data = ClipStore.shared.blobData(hash) else { return nil }
        let info = await Task.detached(priority: .userInitiated, operation: {
            Self.readInfo(data)
        }).value
        infos[hash] = info
        return info
    }

    private nonisolated static func readInfo(_ data: Data) -> ImageBlobInfo {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return ImageBlobInfo(pixelWidth: nil, pixelHeight: nil, byteCount: data.count, type: nil)
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let type = CGImageSourceGetType(source)
            .flatMap { UTType($0 as String)?.preferredFilenameExtension?.uppercased() }
        return ImageBlobInfo(
            pixelWidth: props?[kCGImagePropertyPixelWidth] as? Int,
            pixelHeight: props?[kCGImagePropertyPixelHeight] as? Int,
            byteCount: data.count,
            type: type
        )
    }

    /// Returns a Sendable CGImage so the heavy decode can cross the actor boundary safely.
    private nonisolated static func downsample(_ data: Data, maxPixel: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// A small rounded thumbnail for an image clip — loaded asynchronously (photo-glyph placeholder
/// until ready, and as a fallback if the blob is missing/unreadable, e.g. a lost encryption key).
struct ClipThumbnail: View {
    let hash: String?
    var size: CGFloat = 26
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
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
        .task(id: hash) {
            guard let hash else { image = nil; return }
            image = await ThumbnailCache.shared.thumbnail(for: hash, maxPixel: size * 2)
        }
    }
}
