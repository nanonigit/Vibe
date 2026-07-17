import AVFoundation
import Foundation

public struct AudioMetadata: Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var albumArtist: String
    public var genre: String
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
        return result
    }
}
