import AVFoundation
import Foundation

public struct AudioMetadata: Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var albumArtist: String
    public var genre: String
    public var isCompilation: Bool
    public var discNumber: Int?
    public var trackNumber: Int?
    public var duration: Double
    public var bitrate: Int?
    public var hasArtwork: Bool
}

public enum AudioMetadataReader {
    public static func read(url: URL) async -> AudioMetadata {
        let fallbackTitle = url.deletingPathExtension().lastPathComponent
        var result = AudioMetadata(
            title: fallbackTitle,
            artist: "",
            album: "",
            albumArtist: "",
            genre: "",
            isCompilation: false,
            discNumber: nil,
            trackNumber: nil,
            duration: 0,
            bitrate: nil,
            hasArtwork: false
        )

        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        if let duration = try? await asset.load(.duration), duration.isNumeric {
            result.duration = max(0, duration.seconds)
        }
        if let tracks = try? await asset.loadTracks(withMediaType: .audio), let audioTrack = tracks.first,
           let rate = try? await audioTrack.load(.estimatedDataRate), rate > 0 {
            result.bitrate = Int(rate)
        }
        guard let metadata = try? await asset.load(.commonMetadata) else { return result }

        for item in metadata {
            let key = item.commonKey?.rawValue ?? ""
            switch key {
            case AVMetadataKey.commonKeyTitle.rawValue:
                if let value = try? await item.load(.stringValue), !value.isEmpty { result.title = value }
            case AVMetadataKey.commonKeyArtist.rawValue:
                if let value = try? await item.load(.stringValue) { result.artist = value }
            case AVMetadataKey.commonKeyAlbumName.rawValue:
                if let value = try? await item.load(.stringValue) { result.album = value }
            case AVMetadataKey.commonKeyCreator.rawValue:
                if let value = try? await item.load(.stringValue) { result.albumArtist = value }
            case AVMetadataKey.commonKeyType.rawValue:
                if let value = try? await item.load(.stringValue) { result.genre = value }
            case AVMetadataKey.commonKeyArtwork.rawValue:
                if (try? await item.load(.dataValue)) != nil { result.hasArtwork = true }
            default:
                break
            }
        }
        if url.pathExtension.lowercased() == "mp3",
           let info = try? AudioMetadataWriter.infoDictionary(at: url) {
            result.isCompilation = Self.booleanValue(info["compilation"])
            result.discNumber = Self.integerValue(info["disc number"]) ?? result.discNumber
            result.trackNumber = Self.integerValue(info["track number"]) ?? result.trackNumber
            if let value = info["album artist"] as? String { result.albumArtist = value }
        }
        return result
    }

    private static func integerValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func booleanValue(_ value: Any?) -> Bool {
        if let number = value as? NSNumber { return number.boolValue }
        guard let string = value as? String else { return false }
        return ["1", "true", "yes"].contains(string.lowercased())
    }
}
