import AppKit
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Writes original image payloads and small thumbnails to disk.
///
/// Everything goes through ImageIO so full-resolution bitmaps are never materialised as `NSImage`
/// in this process; the only pixels we keep around are 120pt-tall thumbnails behind an `NSCache`.
final class ImageStore: @unchecked Sendable {
    struct StoredImage: Sendable {
        let imageFile: String
        let thumbFile: String
        let width: Int
        let height: Int
        let byteSize: Int
    }

    enum ImageStoreError: Error {
        case unreadable
        case encodeFailed
    }

    let blobsDirectory: URL
    private let thumbnailCache = NSCache<NSString, NSImage>()

    init(blobsDirectory: URL) {
        self.blobsDirectory = blobsDirectory
        thumbnailCache.countLimit = 96
        try? FileManager.default.createDirectory(at: blobsDirectory, withIntermediateDirectories: true)
    }

    // MARK: Writing

    /// Persists `data` as a PNG (converting from TIFF when needed) and produces a thumbnail.
    func store(data: Data, uti: String, hash: String) throws -> StoredImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw ImageStoreError.unreadable
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let width = (properties[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? Int) ?? 0

        let imageFile = "\(hash).png"
        let thumbFile = "\(hash)_thumb.png"
        let imageURL = blobsDirectory.appendingPathComponent(imageFile)
        let thumbURL = blobsDirectory.appendingPathComponent(thumbFile)

        let byteSize: Int
        if UTType(uti) == .png {
            try data.write(to: imageURL, options: .atomic)
            byteSize = data.count
        } else {
            // Re-encode via ImageIO: no NSImage, no intermediate bitmap owned by us.
            guard let destination = CGImageDestinationCreateWithURL(imageURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                throw ImageStoreError.encodeFailed
            }
            CGImageDestinationAddImageFromSource(destination, source, 0, nil)
            guard CGImageDestinationFinalize(destination) else { throw ImageStoreError.encodeFailed }
            byteSize = (try? FileManager.default.attributesOfItem(atPath: imageURL.path)[.size] as? Int) ?? data.count
        }

        try writeThumbnail(from: source, width: width, height: height, to: thumbURL)
        return StoredImage(imageFile: imageFile, thumbFile: thumbFile, width: width, height: height, byteSize: byteSize)
    }

    private func writeThumbnail(from source: CGImageSource, width: Int, height: Int, to url: URL) throws {
        let targetHeight = Int(Constants.thumbnailMaxHeight * Constants.thumbnailScale)
        // kCGImageSourceThumbnailMaxPixelSize bounds the *larger* dimension, so scale it to land on the height cap.
        var maxPixel = targetHeight
        if width > height, height > 0 {
            maxPixel = min(Int(Double(targetHeight) * Double(width) / Double(height)), targetHeight * 8)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ImageStoreError.encodeFailed
        }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImageStoreError.encodeFailed }
    }

    // MARK: Reading

    func thumbnail(named file: String) -> NSImage? {
        if let cached = thumbnailCache.object(forKey: file as NSString) { return cached }
        let url = blobsDirectory.appendingPathComponent(file)
        guard let image = NSImage(contentsOf: url) else { return nil }
        // Present at points, not pixels, so a 2x thumbnail displays at the 120pt cap.
        image.size = NSSize(width: image.size.width / Constants.thumbnailScale, height: image.size.height / Constants.thumbnailScale)
        thumbnailCache.setObject(image, forKey: file as NSString)
        return image
    }

    func imageData(named file: String) -> Data? {
        try? Data(contentsOf: blobsDirectory.appendingPathComponent(file))
    }

    // MARK: Deleting

    func delete(files: [String]) {
        for file in files {
            thumbnailCache.removeObject(forKey: file as NSString)
            try? FileManager.default.removeItem(at: blobsDirectory.appendingPathComponent(file))
        }
    }

    /// Removes every file in the blobs directory that isn't referenced by `keeping`.
    func pruneOrphans(keeping referenced: Set<String>) {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: blobsDirectory.path) else { return }
        for file in contents where !referenced.contains(file) {
            try? FileManager.default.removeItem(at: blobsDirectory.appendingPathComponent(file))
        }
    }
}

enum ContentHasher {
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ text: String) -> String {
        sha256(Data(text.utf8))
    }
}
