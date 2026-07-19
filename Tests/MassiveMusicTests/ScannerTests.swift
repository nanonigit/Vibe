import Foundation
import Testing
@testable import MassiveMusicCore

@Suite(.serialized)
struct ScannerTests {
    @Test func scanUsesFilenameWhenTagDataIsBrokenAndDifferentialScanDoesNotDuplicate() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MassiveMusicScanner-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-a-valid-mp3-tag".utf8).write(to: directory.appending(path: "broken.mp3"))
        try makeWAV().write(to: directory.appending(path: "tone.wav"))
        let database = try LibraryDatabase(url: directory.appending(path: "library.sqlite"))
        let rootID = try database.addScanRoot(
            displayName: "Fixture", bookmark: Data(), volumeUUID: "fixture", path: directory.path
        )
        let root = SecurityScopedRoot(url: directory, bookmark: Data())
        let scanner = LibraryScanner(database: database)

        try await scanner.scan(root: root, rootID: rootID)
        #expect(try database.trackCount() == 2)
        #expect(try database.pageTracks(query: "broken").tracks.first?.title == "broken")

        try await scanner.scan(root: root, rootID: rootID)
        #expect(try database.trackCount() == 2)
    }

    @Test func missingDriveFailsSafelyAndDatabaseRemainsReadable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MassiveMusicMissing-\(UUID().uuidString)", directoryHint: .isDirectory)
        let database = try LibraryDatabase(url: directory.appending(path: "library.sqlite"))
        let missing = directory.appending(path: "disconnected-drive", directoryHint: .isDirectory)
        let rootID = try database.addScanRoot(
            displayName: "Disconnected", bookmark: Data(), volumeUUID: "missing", path: missing.path
        )
        let scanner = LibraryScanner(database: database)
        var didThrow = false

        do {
            try await scanner.scan(root: SecurityScopedRoot(url: missing, bookmark: Data()), rootID: rootID)
        } catch MassiveMusicError.scanRootUnavailable {
            didThrow = true
        }

        #expect(didThrow)
        #expect(try database.trackCount() == 0)
        #expect(try database.journalMode().lowercased() == "wal")
    }

    @Test func staleScanRootIDIsResolvedFromTheSelectedFolderBeforeCreatingSession() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MassiveMusicStaleRoot-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try makeWAV().write(to: directory.appending(path: "tone.wav"))
        let database = try LibraryDatabase(url: directory.appending(path: "library.sqlite"))
        let scanner = LibraryScanner(database: database)

        // Reproduces a rescan started from a stale view-model/root identifier.
        // The selected folder and bookmark are still valid, so the scanner must
        // resolve/register that folder before inserting the foreign-keyed session.
        try await scanner.scan(
            root: SecurityScopedRoot(url: directory, bookmark: Data()),
            rootID: 9_999
        )

        let root = try #require(database.scanRoots().first)
        #expect(root.lastKnownPath == directory.path)
        #expect(try database.trackCount() == 1)
        #expect(try database.resumableSession(rootID: root.id) == nil)
    }

    private func makeWAV() -> Data {
        let sampleRate: UInt32 = 8_000
        let sampleCount: UInt32 = 800
        let dataSize = sampleCount * 2
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(Data("RIFF".utf8)); append(UInt32(36) + dataSize)
        data.append(Data("WAVEfmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(sampleRate); append(sampleRate * 2); append(UInt16(2)); append(UInt16(16))
        data.append(Data("data".utf8)); append(dataSize)
        data.append(Data(repeating: 0, count: Int(dataSize)))
        return data
    }
}
