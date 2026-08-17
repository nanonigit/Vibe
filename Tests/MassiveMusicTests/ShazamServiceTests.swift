import Testing
import Foundation
import ShazamKit
import AVFoundation
@testable import MassiveMusicCore

struct ShazamServiceTests {
    @Test func testShazamKitBasicRecognition() async throws {
        print("=== Starting testShazamKitBasicRecognition ===")
        
        let generator = SHSignatureGenerator()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100 * 5) else {
            Issue.record("Failed to create PCM buffer")
            return
        }
        buffer.frameLength = 44100 * 5
        try generator.append(buffer, at: nil)
        let signature = generator.signature()
        #expect(signature.duration > 0)
        print("Signature duration: \(signature.duration)s")
    }

    @Test func testRecognizeAudioFilesFromLibrary() async throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbURL = appSupport.appendingPathComponent("MassiveMusic/library.db")
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            print("library.db not found at \(dbURL.path)")
            return
        }

        let database = try LibraryDatabase(url: dbURL)
        let roots = try database.scanRoots()
        print("Found \(roots.count) scan roots")

        // 文字化け曲または通常曲を5曲取得
        let tracks = try database.pageTracks(limit: 5).tracks
        for track in tracks {
            print("--- Testing track: \(track.title) / \(track.artist) (path: \(track.relativePath)) ---")
            guard let root = roots.first(where: { $0.id == track.rootID }) else {
                print("Root not found for track: \(track.id)")
                continue
            }

            do {
                let scope = try SecurityScopedRoot.resolve(bookmark: root.bookmark)
                let audioURL = scope.url.appendingPathComponent(track.relativePath)
                let result = try await scope.withAccess { _ in
                    try await ShazamService.shared.recognizeTrack(fileURL: audioURL)
                }
                if let result {
                    print("✅ SHAZAM MATCHED: Title='\(result.title)', Artist='\(result.artist)', Album='\(result.album ?? "")'")
                } else {
                    print("❌ No match for \(track.relativePath)")
                }
            } catch {
                print("⚠️ Error resolving or recognizing track: \(error)")
            }
        }
    }
}
