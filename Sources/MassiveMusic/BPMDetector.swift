@preconcurrency import AVFoundation
import Foundation

/// On-demand tempo detection for the currently selected practice track.
/// Embedded ID3 tempo wins; otherwise a lightweight onset autocorrelation is
/// used. Analysis is intentionally limited to three minutes and never scans the
/// whole library in the background.
enum BPMDetector {
    static func detect(at url: URL) async throws -> Double? {
        try await Task.detached(priority: .utility) {
            if let embedded = embeddedID3BPM(at: url) { return embedded }
            return try estimateAudioBPM(at: url)
        }.value
    }

    private static func embeddedID3BPM(at url: URL) -> Double? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 2 * 1_024 * 1_024),
              data.count >= 10,
              data.prefix(3) == Data("ID3".utf8) else { return nil }
        let bytes = [UInt8](data)
        let version = bytes[3]
        var offset = 10
        while offset + 10 <= bytes.count {
            let frameID = String(bytes: bytes[offset..<(offset + 4)], encoding: .ascii) ?? ""
            guard frameID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { break }
            let size: Int
            if version == 4 {
                size = bytes[(offset + 4)..<(offset + 8)].reduce(0) { ($0 << 7) | Int($1 & 0x7f) }
            } else {
                size = bytes[(offset + 4)..<(offset + 8)].reduce(0) { ($0 << 8) | Int($1) }
            }
            guard size > 0, offset + 10 + size <= bytes.count else { break }
            if frameID == "TBPM" {
                let payload = Data(bytes[(offset + 10)..<(offset + 10 + size)])
                guard let encoding = payload.first else { return nil }
                let body = payload.dropFirst()
                let text: String?
                switch encoding {
                case 0: text = String(data: body, encoding: .isoLatin1)
                case 1: text = String(data: body, encoding: .utf16)
                case 2: text = String(data: body, encoding: .utf16BigEndian)
                default: text = String(data: body, encoding: .utf8)
                }
                if let value = text.flatMap({ Double($0.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))) }),
                   (30...300).contains(value) { return value }
                return nil
            }
            offset += 10 + size
        }
        return nil
    }

    private static func estimateAudioBPM(at url: URL) throws -> Double? {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard format.sampleRate > 0, format.channelCount > 0 else { return nil }
        let frameCount: AVAudioFrameCount = 2_048
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        let maximumFrames = AVAudioFramePosition(format.sampleRate * 180)
        var consumed: AVAudioFramePosition = 0
        var energy: [Double] = []
        energy.reserveCapacity(Int(maximumFrames / AVAudioFramePosition(frameCount)))

        while consumed < min(file.length, maximumFrames) {
            try Task.checkCancellation()
            let remaining = min(AVAudioFramePosition(frameCount), min(file.length, maximumFrames) - consumed)
            try file.read(into: buffer, frameCount: AVAudioFrameCount(remaining))
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { break }
            var sum = 0.0
            for channel in 0..<Int(format.channelCount) {
                let samples = channels[channel]
                for frame in 0..<Int(buffer.frameLength) {
                    let value = Double(samples[frame])
                    sum += value * value
                }
            }
            let count = Double(Int(buffer.frameLength) * Int(format.channelCount))
            energy.append(log1p(sqrt(sum / max(1, count)) * 100))
            consumed += AVAudioFramePosition(buffer.frameLength)
        }
        guard energy.count >= 100 else { return nil }

        var onset = Array(repeating: 0.0, count: energy.count)
        for index in 1..<energy.count { onset[index] = max(0, energy[index] - energy[index - 1]) }
        let mean = onset.reduce(0, +) / Double(onset.count)
        onset = onset.map { max(0, $0 - mean * 0.55) }
        let envelopeRate = format.sampleRate / Double(frameCount)
        var bestBPM: Double?
        var bestScore = 0.0
        for bpm in stride(from: 60.0, through: 200.0, by: 0.5) {
            let lag = max(1, Int((60 * envelopeRate / bpm).rounded()))
            guard lag < onset.count else { continue }
            var score = 0.0
            for index in lag..<onset.count { score += onset[index] * onset[index - lag] }
            score /= Double(onset.count - lag)
            if score > bestScore { bestScore = score; bestBPM = bpm }
        }
        guard bestScore > 0.000_01 else { return nil }
        return bestBPM
    }
}
