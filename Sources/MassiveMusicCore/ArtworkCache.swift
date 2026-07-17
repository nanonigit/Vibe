@preconcurrency import AVFoundation
import AppKit
import Foundation
import ImageIO

public actor ArtworkCache {
    public static let shared = ArtworkCache()

    private let memory = NSCache<NSString, NSImage>()
    private let fileManager = FileManager.default
    private let diskLimitBytes: Int64
    private let cacheDirectory: URL

    public init(memoryLimitBytes: Int = 64 * 1_024 * 1_024, diskLimitBytes: Int64 = 2 * 1_024 * 1_024 * 1_024) {
        memory.totalCostLimit = memoryLimitBytes
        self.diskLimitBytes = diskLimitBytes
        let manager = FileManager.default
        let base = (try? manager.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? manager.temporaryDirectory
        cacheDirectory = base.appending(path: "MassiveMusic/Artwork", directoryHint: .isDirectory)
        try? manager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    public func image(trackID: Int64, audioURL: URL, maxPixelSize: Int = 512) async -> NSImage? {
        let key = NSString(string: "\(trackID)-\(maxPixelSize)")
        if let cached = memory.object(forKey: key) { return cached }
        let diskURL = cacheDirectory.appending(path: "\(key).jpg")
        if let image = NSImage(contentsOf: diskURL) {
            memory.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height * 4))
            return image
        }
        let asset = AVURLAsset(url: audioURL)
        guard let metadata = try? await asset.load(.commonMetadata) else { return nil }
        for item in metadata where item.commonKey == .commonKeyArtwork {
            guard let data = try? await item.load(.dataValue),
                  let thumbnail = Self.thumbnail(data: data, maxPixelSize: maxPixelSize) else { continue }
            memory.setObject(thumbnail, forKey: key, cost: maxPixelSize * maxPixelSize * 4)
            if let jpeg = thumbnail.tiffRepresentation.flatMap({ NSBitmapImageRep(data: $0) })?.representation(
                using: .jpeg, properties: [.compressionFactor: 0.82]
            ) {
                try? jpeg.write(to: diskURL, options: .atomic)
                trimDiskIfNeeded()
            }
            return thumbnail
        }
        return nil
    }

    public func imageURL(trackID: Int64, audioURL: URL, maxPixelSize: Int = 512) async -> URL? {
        let key = NSString(string: "\(trackID)-\(maxPixelSize)")
        let diskURL = cacheDirectory.appending(path: "\(key).jpg")
        if fileManager.fileExists(atPath: diskURL.path) { return diskURL }
        // If the disk entry was removed independently, force extraction again
        // instead of returning a memory-only image that the URL-based UI cannot use.
        memory.removeObject(forKey: key)
        guard await image(trackID: trackID, audioURL: audioURL, maxPixelSize: maxPixelSize) != nil,
              fileManager.fileExists(atPath: diskURL.path) else { return nil }
        return diskURL
    }

    public func invalidate(trackID: Int64) {
        for size in [256, 512, 1024] {
            memory.removeObject(forKey: NSString(string: "\(trackID)-\(size)"))
        }
        guard let files = try? fileManager.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return }
        for file in files where file.lastPathComponent.hasPrefix("\(trackID)-") {
            try? fileManager.removeItem(at: file)
        }
    }

    private static func thumbnail(data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }

    private func trimDiskIfNeeded() {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey]
        guard let files = try? fileManager.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) else { return }
        let entries = files.compactMap { url -> (URL, Int64, Date)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, Int64(values.fileSize ?? 0), values.contentAccessDate ?? values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(Int64(0)) { $0 + $1.1 }
        guard total > diskLimitBytes else { return }
        for entry in entries.sorted(by: { $0.2 < $1.2 }) where total > diskLimitBytes {
            try? fileManager.removeItem(at: entry.0)
            total -= entry.1
        }
    }
}
