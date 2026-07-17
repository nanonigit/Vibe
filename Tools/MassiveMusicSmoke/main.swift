@preconcurrency import AVFoundation
import Foundation
import MassiveMusicCore

private func runSmokeTest() async {
    do {
            guard let rootPath = CommandLine.arguments.dropFirst().first else {
                throw SmokeError.missingFolder
            }
            let rootURL = URL(filePath: rootPath, directoryHint: .isDirectory)
            let working = FileManager.default.temporaryDirectory
                .appending(path: "MassiveMusicSmoke-\(UUID().uuidString)", directoryHint: .isDirectory)
            let database = try LibraryDatabase(url: working.appending(path: "smoke.sqlite"))
            let rootID = try database.addScanRoot(
                displayName: rootURL.lastPathComponent,
                bookmark: Data(),
                volumeUUID: "smoke",
                path: rootURL.path
            )
            let scanner = LibraryScanner(database: database)
            try await scanner.scan(
                root: SecurityScopedRoot(url: rootURL, bookmark: Data()),
                rootID: rootID
            )
            guard let track = try database.pageTracks(limit: 1, availableOnly: true).tracks.first else {
                throw SmokeError.noTrack
            }
            let audioURL = rootURL.appending(path: track.relativePath)
            let player = AVPlayer(url: audioURL)
            player.play()
            try await Task.sleep(for: .milliseconds(1_500))
            let elapsed = player.currentTime().seconds
            guard elapsed.isFinite, elapsed > 0.05, player.error == nil else {
                throw SmokeError.playbackDidNotAdvance(elapsed)
            }
            player.pause()
            let result: [String: Any] = [
                "scannedTracks": try database.trackCount(),
                "track": track.filename,
                "durationSeconds": track.duration,
                "playbackAdvancedSeconds": elapsed,
                "format": track.format,
                "status": "passed"
            ]
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            exit(0)
    } catch {
        FileHandle.standardError.write(Data("Smoke test failed: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

Task { await runSmokeTest() }
dispatchMain()

private enum SmokeError: LocalizedError {
    case missingFolder
    case noTrack
    case playbackDidNotAdvance(Double)

    var errorDescription: String? {
        switch self {
        case .missingFolder: "Usage: MassiveMusicSmoke <audio-folder>"
        case .noTrack: "The scanner did not register an audio track."
        case let .playbackDidNotAdvance(seconds): "AVPlayer did not advance (\(seconds) seconds)."
        }
    }
}
