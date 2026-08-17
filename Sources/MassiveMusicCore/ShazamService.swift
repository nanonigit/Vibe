import Foundation
import ShazamKit
import AVFoundation

public struct ShazamRecognizedMetadata: Sendable {
    public let title: String
    public let artist: String
    public let album: String?
    public let genre: String?
    public let artworkURL: URL?
    public let appleMusicURL: URL?
    public let isrc: String?

    public init(
        title: String,
        artist: String,
        album: String? = nil,
        genre: String? = nil,
        artworkURL: URL? = nil,
        appleMusicURL: URL? = nil,
        isrc: String? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.genre = genre
        self.artworkURL = artworkURL
        self.appleMusicURL = appleMusicURL
        self.isrc = isrc
    }
}

public struct ShazamRecognitionResult: Identifiable, Sendable {
    public var id: Int64 { track.id }
    public let track: Track
    public let metadata: ShazamRecognizedMetadata

    public init(track: Track, metadata: ShazamRecognizedMetadata) {
        self.track = track
        self.metadata = metadata
    }
}

public final class ShazamService: NSObject, SHSessionDelegate, @unchecked Sendable {
    public static let shared = ShazamService()
    
    private var session: SHSession?
    private var matchContinuation: CheckedContinuation<ShazamRecognizedMetadata?, Error>?

    private override init() {
        super.init()
    }

    public func recognizeTrack(fileURL: URL) async throws -> ShazamRecognizedMetadata? {
        // 冒頭5秒〜17秒（12秒間）を AVAssetReader で確実にデコードして照合
        if let result = try await extractAndMatch(fileURL: fileURL, startSeconds: 5, durationSeconds: 12) {
            return result
        }
        // イントロで特定できない場合、サビ/中盤30秒〜42秒（12秒間）で照合
        if let result = try await extractAndMatch(fileURL: fileURL, startSeconds: 30, durationSeconds: 12) {
            return result
        }
        return nil
    }

    private func extractAndMatch(fileURL: URL, startSeconds: Double, durationSeconds: Double) async throws -> ShazamRecognizedMetadata? {
        let asset = AVURLAsset(url: fileURL)
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            return nil
        }
        guard let audioTrack = tracks.first else { return nil }

        let duration = try await asset.load(.duration).seconds
        let actualStart = min(startSeconds, max(0, duration - durationSeconds))
        let actualDuration = min(durationSeconds, max(0, duration - actualStart))
        guard actualDuration >= 4.0 else { return nil } // 最低4秒以上

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            return nil
        }

        let timeRange = CMTimeRange(
            start: CMTime(seconds: actualStart, preferredTimescale: 44100),
            duration: CMTime(seconds: actualDuration, preferredTimescale: 44100)
        )
        reader.timeRange = timeRange

        // 44.1kHz, 16-bit, Mono PCM に確実にデコード
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        trackOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(trackOutput) else { return nil }
        reader.add(trackOutput)

        guard reader.startReading() else { return nil }

        let signatureGenerator = SHSignatureGenerator()
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 44100,
            channels: 1,
            interleaved: true
        ) else { return nil }

        var hasAppendedBuffer = false

        while reader.status == .reading {
            guard let sampleBuffer = trackOutput.copyNextSampleBuffer() else { break }
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

            let length = CMBlockBufferGetDataLength(blockBuffer)
            guard length > 0 else { continue }

            let frameCount = AVAudioFrameCount(length / 2) // 16-bit mono = 2 bytes per frame
            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { continue }
            pcmBuffer.frameLength = frameCount

            guard let channelData = pcmBuffer.int16ChannelData else { continue }
            var status = CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: channelData[0])
            guard status == kCMBlockBufferNoErr else { continue }

            do {
                try signatureGenerator.append(pcmBuffer, at: nil)
                hasAppendedBuffer = true
            } catch {
                break
            }
        }

        guard hasAppendedBuffer else { return nil }

        let signature = signatureGenerator.signature()
        guard signature.duration >= 3.0 else { return nil }

        return try await withCheckedThrowingContinuation { continuation in
            let session = SHSession()
            self.session = session
            self.matchContinuation = continuation
            session.delegate = self
            session.match(signature)
        }
    }

    // MARK: - SHSessionDelegate

    public func session(_ session: SHSession, didFind match: SHMatch) {
        let continuation = matchContinuation
        matchContinuation = nil
        self.session = nil

        guard let item = match.mediaItems.first else {
            continuation?.resume(returning: nil)
            return
        }

        let metadata = ShazamRecognizedMetadata(
            title: item.title ?? "",
            artist: item.artist ?? "",
            album: item.subtitle,
            genre: item.genres.first,
            artworkURL: item.artworkURL,
            appleMusicURL: item.appleMusicURL,
            isrc: item.isrc
        )
        continuation?.resume(returning: metadata)
    }

    public func session(_ session: SHSession, didNotFindMatchFor signature: SHSignature, error: Error?) {
        let continuation = matchContinuation
        matchContinuation = nil
        self.session = nil

        if let error = error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume(returning: nil)
        }
    }
}
