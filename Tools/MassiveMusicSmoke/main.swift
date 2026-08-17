@preconcurrency import AVFoundation
import Foundation
import MassiveMusicCore
import ShazamKit

private func runShazamTest() async {
    let arguments = CommandLine.arguments.dropFirst()
    
    // 引数にファイルパスが指定されている場合
    if let filePath = arguments.first {
        let fileURL = URL(fileURLWithPath: filePath)
        print("🔍 Testing Shazam recognition for: \(fileURL.path)")
        do {
            let result = try await ShazamService.shared.recognizeTrack(fileURL: fileURL)
            if let result {
                print("========================================")
                print("🎉 SUCCESS! SHAZAM IDENTIFIED SONG:")
                print("   Title:  \(result.title)")
                print("   Artist: \(result.artist)")
                print("   Album:  \(result.album ?? "N/A")")
                print("   Genre:  \(result.genre ?? "N/A")")
                print("========================================")
                exit(0)
            } else {
                print("❌ Shazam returned no match for this audio file.")
                exit(1)
            }
        } catch {
            print("🚨 ShazamService threw error: \(error)")
            exit(1)
        }
    }

    // 引数がない場合、library.db から曲を取得してテスト
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let dbURL = appSupport.appendingPathComponent("MassiveMusic/library.db")
    guard FileManager.default.fileExists(atPath: dbURL.path) else {
        print("library.db not found at \(dbURL.path)")
        exit(1)
    }

    do {
        let database = try LibraryDatabase(url: dbURL)
        let roots = try database.scanRoots()
        print("Found \(roots.count) scan roots.")

        let tracks = try database.pageTracks(limit: 10).tracks
        for track in tracks {
            print("\n----------------------------------------")
            print("Testing track [\(track.id)]: \(track.title) / \(track.artist)")
            print("Relative path: \(track.relativePath)")
            guard let root = roots.first(where: { $0.id == track.rootID }) else {
                print("Scan root \(track.rootID) not found.")
                continue
            }

            let scope = try SecurityScopedRoot.resolve(bookmark: root.bookmark)
            let audioURL = scope.url.appendingPathComponent(track.relativePath)
            let result = try await scope.withAccess { _ in
                try await ShazamService.shared.recognizeTrack(fileURL: audioURL)
            }
            if let result {
                print("🎉 MATCHED: \(result.title) by \(result.artist) (Album: \(result.album ?? ""))")
            } else {
                print("❌ No match")
            }
        }
    } catch {
        print("Database error: \(error)")
        exit(1)
    }
}

Task { await runShazamTest() }
dispatchMain()
