import AVFoundation
import Foundation
import Testing
@testable import MassiveMusicCore

@Suite(.serialized)
struct AudioMetadataWriterTests {
    @Test func reservesCapacityForSafeWriteAndRollback() {
        #expect(AudioMetadataWriter.requiredDestinationCapacity(forFileSize: 1) == 32 * 1_024 * 1_024)
        #expect(AudioMetadataWriter.requiredDestinationCapacity(forFileSize: 10 * 1_024 * 1_024) == 36 * 1_024 * 1_024)
    }

    @Test func removesLeadingHalfWidthAndFullWidthSpacesFromTitleBeforeWriting() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MassiveMusicLeadingTitleSpaces-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "fixture.wav")
        try makeWAV().write(to: url)
        let originalAudioBytes = try Data(contentsOf: url).suffix(1_600)
        let track = Track(
            rootID: 1, relativePath: "fixture.wav", filename: "fixture.wav", title: "Old",
            fileSize: Int64((try Data(contentsOf: url)).count), modifiedAt: .now, format: "wav"
        )
        var edit = TrackMetadataEdit(track: track)
        edit.title = " 　A Man Needs To Be Told"

        try AudioMetadataWriter.write(edit, to: url)

        #expect(try AudioMetadataWriter.infoDictionary(at: url)["title"] as? String == "A Man Needs To Be Told")
        #expect(try Data(contentsOf: url).range(of: Data(originalAudioBytes)) != nil)
    }

    @Test func preservesSpacesInsideAndAfterTitle() throws {
        let track = Track(
            rootID: 1, relativePath: "fixture.mp3", filename: "fixture.mp3",
            title: " 　A  Man　", fileSize: 0, modifiedAt: .now, format: "mp3"
        )

        let edit = TrackMetadataEdit(track: track).normalizingLeadingTitleSpaces()

        #expect(edit.title == "A  Man　")
    }

    @Test func writesRIFFInfoWithoutChangingPCMBytes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MassiveMusicMetadata-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "fixture.wav")
        try makeWAV().write(to: url)
        let originalAudioBytes = try Data(contentsOf: url).suffix(1_600)
        let track = Track(
            rootID: 1, relativePath: "fixture.wav", filename: "fixture.wav", title: "Old",
            fileSize: Int64((try Data(contentsOf: url)).count), modifiedAt: Date(), format: "wav"
        )
        var edit = TrackMetadataEdit(track: track)
        edit.title = "Verified Title"
        edit.artist = "Verified Artist"
        edit.album = "Verified Album"
        edit.genre = "Jazz"
        edit.trackNumber = 4

        try AudioMetadataWriter.write(edit, to: url)
        let info = try AudioMetadataWriter.infoDictionary(at: url)
        #expect(info["title"] as? String == "Verified Title")
        #expect(info["artist"] as? String == "Verified Artist")
        #expect(info["track number"] as? String == "4")
        #expect(try Data(contentsOf: url).range(of: Data(originalAudioBytes)) != nil)
    }

    @Test func writesM4AMovieHeaderWithoutChangingMediaBytes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MassiveMusicM4A-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "fixture.m4a")
        try makeM4A(at: url)
        let originalMedia = try m4aMediaData(at: url)
        let track = Track(
            rootID: 1, relativePath: "fixture.m4a", filename: "fixture.m4a", title: "Old",
            artist: "Old Artist", album: "Old Album",
            fileSize: Int64((try Data(contentsOf: url)).count), modifiedAt: .now, format: "m4a"
        )
        var edit = TrackMetadataEdit(track: track)
        edit.title = " 　M4A Title"
        edit.artist = "M4A Artist"
        edit.album = "M4A Album"
        edit.trackNumber = 3
        edit.discNumber = 2

        try AudioMetadataWriter.write(edit, to: url)

        let info = try AudioMetadataWriter.infoDictionary(at: url)
        #expect(info["title"] as? String == "M4A Title")
        #expect(info["artist"] as? String == "M4A Artist")
        #expect(info["album"] as? String == "M4A Album")
        #expect(info["track number"] as? String == "3")
        #expect(info["disc number"] as? String == "2")
        #expect(try m4aMediaData(at: url) == originalMedia)
    }

    @Test func writesRealCopiedFixtureWhenProvided() throws {
        guard let fixturePath = ProcessInfo.processInfo.environment["MASSIVEMUSIC_METADATA_FIXTURE"] else { return }
        let fixture = URL(filePath: fixturePath)
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MassiveMusicRealMetadata-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let copy = directory.appending(path: fixture.lastPathComponent)
        try FileManager.default.copyItem(at: fixture, to: copy)
        let track = Track(
            rootID: 1, relativePath: copy.lastPathComponent, filename: copy.lastPathComponent,
            title: "Old", fileSize: Int64((try Data(contentsOf: copy)).count),
            modifiedAt: Date(), format: copy.pathExtension.lowercased()
        )
        var edit = TrackMetadataEdit(track: track)
        edit.title = " 　MassiveMusic Metadata Probe"
        edit.artist = "MassiveMusic Test"
        edit.album = "Safe Copy"
        edit.trackNumber = 7
        let originalMP3Audio = copy.pathExtension.lowercased() == "mp3"
            ? try mp3AudioPayload(at: copy) : nil
        try AudioMetadataWriter.write(edit, to: copy)
        let info = try AudioMetadataWriter.infoDictionary(at: copy)
        #expect(info["title"] as? String == "MassiveMusic Metadata Probe")
        #expect(info["artist"] as? String == edit.artist)
        #expect(info["track number"] as? String == "7")
        if let originalMP3Audio {
            #expect(try mp3AudioPayload(at: copy) == originalMP3Audio)
        }
    }

    @Test func repairsRealLegacyFixtureWhenProvided() throws {
        guard let fixturePath = ProcessInfo.processInfo.environment["MASSIVEMUSIC_LEGACY_ID3_FIXTURE"] else { return }
        let fixture = URL(filePath: fixturePath)
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MassiveMusicLegacyID3-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let copy = directory.appending(path: fixture.lastPathComponent)
        try FileManager.default.copyItem(at: fixture, to: copy)
        let originalAudio = try mp3AudioPayload(at: copy)
        let track = Track(
            rootID: 1, relativePath: copy.lastPathComponent, filename: copy.lastPathComponent,
            title: "Baby Break It Down", artist: "The Rolling Stones", album: "Voodoo Lounge",
            fileSize: Int64((try Data(contentsOf: copy)).count), modifiedAt: .now, format: "mp3"
        )
        try AudioMetadataWriter.write(TrackMetadataEdit(track: track), to: copy, repairingCorruptID3: true)
        let repaired = try Data(contentsOf: copy)
        #expect(repaired.prefix(4) == Data([0x49, 0x44, 0x33, 0x03]))
        #expect(try mp3AudioPayload(at: copy) == originalAudio)
        #expect(try AudioMetadataWriter.infoDictionary(at: copy)["title"] as? String == track.title)
    }

    @Test func writesWhenParentDirectoryDoesNotAllowSiblingCreation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MassiveMusicNoSibling-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appending(path: "fixture.wav")
        try makeWAV().write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)

        let track = Track(
            rootID: 1, relativePath: "fixture.wav", filename: "fixture.wav", title: "Old",
            fileSize: Int64((try Data(contentsOf: url)).count), modifiedAt: .now, format: "wav"
        )
        var edit = TrackMetadataEdit(track: track)
        edit.title = "No Sibling Required"
        edit.artist = "MassiveMusic"
        try AudioMetadataWriter.write(edit, to: url)
        #expect(try AudioMetadataWriter.infoDictionary(at: url)["title"] as? String == edit.title)
    }

    @Test func writesID3v23AndPreservesArtworkAndAudioBytes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MassiveMusicID3-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "fixture.mp3")
        let artworkPayload = Data([0, 0x69, 0x6D, 0x61, 0x67, 0x65])
        let audioBytes = Data(repeating: 0xA5, count: 4_096)
        try makeID3v23(title: "Old", artworkPayload: artworkPayload, audioBytes: audioBytes).write(to: url)
        let track = Track(
            rootID: 1, relativePath: "fixture.mp3", filename: "fixture.mp3", title: "Old",
            fileSize: Int64((try Data(contentsOf: url)).count), modifiedAt: .now, format: "mp3"
        )
        var edit = TrackMetadataEdit(track: track)
        edit.title = "\t / 4 Lo"
        edit.artist = "確認用アーティスト"
        edit.album = "確認用アルバム"
        edit.trackNumber = 12

        try AudioMetadataWriter.write(edit, to: url)
        let output = try Data(contentsOf: url)
        let info = try AudioMetadataWriter.infoDictionary(at: url)
        #expect(info["title"] as? String == edit.title)
        #expect(info["artist"] as? String == edit.artist)
        #expect(info["album"] as? String == edit.album)
        #expect(info["track number"] as? String == "12")
        #expect(output.containsSubsequence(Data("APIC".utf8)))
        #expect(output.containsSubsequence(artworkPayload))
        #expect(output.suffix(audioBytes.count) == audioBytes)
    }

    @Test func writesAndClearsCompilationTagWithoutChangingAudioBytes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MassiveMusicCompilation-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "fixture.mp3")
        let audioBytes = Data(repeating: 0xA5, count: 4_096)
        try makeID3v23(title: "Song", artworkPayload: Data(), audioBytes: audioBytes).write(to: url)
        let track = Track(
            rootID: 1, relativePath: "fixture.mp3", filename: "fixture.mp3", title: "Song",
            artist: "Individual Artist", album: "Compilation",
            fileSize: Int64((try Data(contentsOf: url)).count), modifiedAt: .now, format: "mp3"
        )
        var edit = TrackMetadataEdit(track: track)
        edit.isCompilation = true

        try AudioMetadataWriter.write(edit, to: url)
        #expect(try AudioMetadataWriter.infoDictionary(at: url)["compilation"] as? String == "1")
        #expect(try Data(contentsOf: url).suffix(audioBytes.count) == audioBytes)

        edit.isCompilation = false
        try AudioMetadataWriter.write(edit, to: url)
        #expect(try AudioMetadataWriter.infoDictionary(at: url)["compilation"] == nil)
        #expect(try Data(contentsOf: url).suffix(audioBytes.count) == audioBytes)
    }

    @Test func explicitlyRepairsMalformedID3FrameWithoutChangingAudioBytes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MassiveMusicMalformedID3-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "fixture.mp3")
        var audioBytes = Data([0xFF, 0xFB])
        audioBytes.append(Data(repeating: 0xA5, count: 8_190))
        try makeMalformedID3v24(audioBytes: audioBytes).write(to: url)
        let track = Track(
            rootID: 1, relativePath: "fixture.mp3", filename: "fixture.mp3", title: "Old",
            artist: "Old Artist", album: "Old Album", discNumber: 2, trackNumber: 14,
            fileSize: Int64((try Data(contentsOf: url)).count), modifiedAt: .now, format: "mp3"
        )
        var edit = TrackMetadataEdit(track: track)
        edit.title = "Repaired Title"

        #expect(throws: (any Error).self) {
            try AudioMetadataWriter.write(edit, to: url)
        }
        try AudioMetadataWriter.write(edit, to: url, repairingCorruptID3: true)

        let output = try Data(contentsOf: url)
        let info = try AudioMetadataWriter.infoDictionary(at: url)
        #expect(info["title"] as? String == "Repaired Title")
        #expect(info["artist"] as? String == "Old Artist")
        #expect(info["album"] as? String == "Old Album")
        #expect(info["track number"] as? String == "14")
        #expect(output.suffix(audioBytes.count) == audioBytes)
    }

    @Test func repairsIncorrectID3SizeAfterValidatingConsecutiveMPEGFrames() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MassiveMusicWrongID3Size-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "fixture.mp3")
        let audioBytes = makeMPEG1Layer3Frames(count: 3)
        var damaged = Data("ID3".utf8)
        damaged.append(contentsOf: [3, 0, 0])
        // Declares 127 bytes although the damaged tag payload contains only 16.
        damaged.append(contentsOf: [0, 0, 0, 127])
        damaged.append(Data(repeating: 0, count: 16))
        damaged.append(audioBytes)
        try damaged.write(to: url)
        let track = Track(
            rootID: 1, relativePath: "fixture.mp3", filename: "fixture.mp3", title: "Ｏｌｄ",
            artist: "Artist", album: "Album", fileSize: Int64(damaged.count),
            modifiedAt: .now, format: "mp3"
        )
        var edit = TrackMetadataEdit(track: track)
        edit.title = "Old"

        try AudioMetadataWriter.write(edit, to: url, repairingCorruptID3: true)

        let output = try Data(contentsOf: url)
        #expect(try AudioMetadataWriter.infoDictionary(at: url)["title"] as? String == "Old")
        #expect(output.suffix(audioBytes.count) == audioBytes)
    }

    @Test func explicitlyUpgradesID3v22AndPreservesArtworkAndAudioBytes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MassiveMusicID3v22-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "fixture.mp3")
        let artworkBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x11, 0x22, 0xFF, 0xD9])
        var audioBytes = Data([0xFF, 0xFB])
        audioBytes.append(Data(repeating: 0xA5, count: 8_190))
        try makeID3v22(title: "Old Title", artworkBytes: artworkBytes, audioBytes: audioBytes).write(to: url)
        let track = Track(
            rootID: 1, relativePath: "fixture.mp3", filename: "fixture.mp3", title: "Old Title",
            artist: "The Rolling Stones", album: "Voodoo Lounge", trackNumber: 1,
            fileSize: Int64((try Data(contentsOf: url)).count), modifiedAt: .now, format: "mp3"
        )
        var edit = TrackMetadataEdit(track: track)
        edit.title = "Baby Break It Down"

        do {
            try AudioMetadataWriter.write(edit, to: url)
            Issue.record("Expected ID3v2.2 to require explicit repair confirmation")
        } catch {
            #expect((error as? MassiveMusicError)?.isRepairableID3Damage == true)
        }
        try AudioMetadataWriter.write(edit, to: url, repairingCorruptID3: true)

        let output = try Data(contentsOf: url)
        let info = try AudioMetadataWriter.infoDictionary(at: url)
        #expect(output.prefix(4) == Data([0x49, 0x44, 0x33, 0x03]))
        #expect(info["title"] as? String == "Baby Break It Down")
        #expect(info["artist"] as? String == "The Rolling Stones")
        #expect(info["album"] as? String == "Voodoo Lounge")
        #expect(output.containsSubsequence(Data("APIC".utf8)))
        #expect(output.containsSubsequence(artworkBytes))
        #expect(output.suffix(audioBytes.count) == audioBytes)
    }

    @Test func explicitlyRebuildsDamagedID3v22FramesWithoutChangingAudioBytes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MassiveMusicDamagedID3v22-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "fixture.mp3")
        var audioBytes = Data([0xFF, 0xFB])
        audioBytes.append(Data(repeating: 0xA5, count: 8_190))
        var damaged = makeID3v22(
            title: "Old Title",
            artworkBytes: Data([0xFF, 0xD8, 0xFF, 0xD9]),
            audioBytes: audioBytes
        )
        // Corrupt the first v2.2 frame allocation while leaving the enclosing
        // tag size and MPEG boundary intact.
        damaged.replaceSubrange(13..<16, with: [0x7F, 0xFF, 0xFF])
        try damaged.write(to: url)
        let track = Track(
            rootID: 1, relativePath: "fixture.mp3", filename: "fixture.mp3", title: "Old Title",
            artist: "Artist", album: "Album", fileSize: Int64(damaged.count),
            modifiedAt: .now, format: "mp3"
        )
        var edit = TrackMetadataEdit(track: track)
        edit.title = "Repaired Title"

        try AudioMetadataWriter.write(edit, to: url, repairingCorruptID3: true)

        let output = try Data(contentsOf: url)
        let info = try AudioMetadataWriter.infoDictionary(at: url)
        #expect(output.prefix(4) == Data([0x49, 0x44, 0x33, 0x03]))
        #expect(info["title"] as? String == "Repaired Title")
        #expect(info["artist"] as? String == "Artist")
        #expect(info["album"] as? String == "Album")
        #expect(output.suffix(audioBytes.count) == audioBytes)
    }

    @Test func convertsLargePreservedID3v24FrameSizesWhenWritingV23() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MassiveMusicID3v24FrameSize-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "fixture.mp3")
        let artworkPayload = Data(repeating: 0x5A, count: 26_299)
        var audioBytes = Data([0xFF, 0xFB])
        audioBytes.append(Data(repeating: 0xA5, count: 8_190))
        try makeID3v24(title: "Old", artworkPayload: artworkPayload, audioBytes: audioBytes).write(to: url)
        let track = Track(
            rootID: 1, relativePath: "fixture.mp3", filename: "fixture.mp3", title: "Old",
            artist: "Artist", album: "Album", fileSize: Int64((try Data(contentsOf: url)).count),
            modifiedAt: .now, format: "mp3"
        )
        var edit = TrackMetadataEdit(track: track)
        edit.title = "Changed"

        try AudioMetadataWriter.write(edit, to: url)

        #expect(try AudioMetadataWriter.infoDictionary(at: url)["title"] as? String == "Changed")
        let output = try Data(contentsOf: url)
        #expect(output.containsSubsequence(artworkPayload))
        #expect(output.suffix(audioBytes.count) == audioBytes)
    }

    @Test func batchChangesPreservePerTrackFieldsAndReplaceMP3Artwork() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MassiveMusicBatchArtwork-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "fixture.mp3")
        let oldArtwork = Data([0, 0x6F, 0x6C, 0x64])
        let newArtwork = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x11, 0x22, 0xFF, 0xD9])
        let audioBytes = Data(repeating: 0x5A, count: 2_048)
        try makeID3v23(title: "Unique Title", artworkPayload: oldArtwork, audioBytes: audioBytes).write(to: url)
        let track = Track(
            rootID: 1, relativePath: "fixture.mp3", filename: "fixture.mp3", title: "Unique Title",
            artist: "Old Artist", album: "Old Album", discNumber: 2, trackNumber: 7,
            fileSize: Int64((try Data(contentsOf: url)).count), modifiedAt: .now, format: "mp3"
        )
        let preservingChanges = BatchMetadataChanges(artist: "Shared Artist", album: "Shared Album")
        let preservingEdit = preservingChanges.applying(to: track)
        #expect(preservingEdit.title == "Unique Title")
        #expect(preservingEdit.discNumber == 2)
        #expect(preservingEdit.trackNumber == 7)

        let changes = BatchMetadataChanges(
            title: "Shared Title", artist: "Shared Artist", album: "Shared Album",
            discNumber: 3, changesDiscNumber: true,
            trackNumber: 10, changesTrackNumber: true, incrementsTrackNumber: true,
            artworkData: newArtwork
        )
        let edit = changes.applying(to: track, offset: 2)
        #expect(edit.title == "Shared Title")
        #expect(edit.discNumber == 3)
        #expect(edit.trackNumber == 12)

        try AudioMetadataWriter.write(edit, to: url)
        let output = try Data(contentsOf: url)
        let info = try AudioMetadataWriter.infoDictionary(at: url)
        #expect(info["title"] as? String == "Shared Title")
        #expect(info["artist"] as? String == "Shared Artist")
        #expect(info["album"] as? String == "Shared Album")
        #expect(info["disc number"] as? String == "3")
        #expect(info["track number"] as? String == "12")
        #expect(output.containsSubsequence(newArtwork))
        #expect(output.suffix(audioBytes.count) == audioBytes)
    }

    @Test func destinationOpenPermissionErrorIsNotMaskedByRollback() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MassiveMusicReadOnly-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: directory.appending(path: "fixture.wav").path)
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appending(path: "fixture.wav")
        try makeWAV().write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: url.path)
        let track = Track(rootID: 1, relativePath: "fixture.wav", filename: "fixture.wav", title: "Old",
                          fileSize: Int64((try Data(contentsOf: url)).count), modifiedAt: .now, format: "wav")
        var edit = TrackMetadataEdit(track: track)
        edit.title = "Should not write"
        do {
            try AudioMetadataWriter.write(edit, to: url)
            Issue.record("Expected a destination write-permission failure")
        } catch {
            let value = error as NSError
            #expect(value.domain == NSCocoaErrorDomain)
            #expect(value.code == CocoaError.fileWriteNoPermission.rawValue)
        }
    }

    @Test func changesAndRestoresActualFixtureWhenExplicitlyAuthorized() throws {
        guard let fixturePath = ProcessInfo.processInfo.environment["MASSIVEMUSIC_DESTRUCTIVE_METADATA_FIXTURE"] else { return }
        let fixture = URL(filePath: fixturePath)
        let original = try AudioMetadataWriter.infoDictionary(at: fixture)
        let track = Track(
            rootID: 1, relativePath: fixture.lastPathComponent, filename: fixture.lastPathComponent,
            title: original["title"] as? String ?? fixture.deletingPathExtension().lastPathComponent,
            artist: original["artist"] as? String ?? "", album: original["album"] as? String ?? "",
            albumArtist: original["album artist"] as? String ?? "", genre: original["genre"] as? String ?? "",
            discNumber: Int(original["disc number"] as? String ?? ""),
            trackNumber: Int(original["track number"] as? String ?? ""),
            fileSize: Int64((try fixture.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0),
            modifiedAt: .now, format: fixture.pathExtension.lowercased()
        )
        let restore = TrackMetadataEdit(track: track)
        defer { try? AudioMetadataWriter.write(restore, to: fixture) }

        var probe = restore
        probe.title = "\(restore.title) [MassiveMusic round-trip probe]"
        try AudioMetadataWriter.write(probe, to: fixture)
        #expect(try AudioMetadataWriter.infoDictionary(at: fixture)["title"] as? String == probe.title)
        try AudioMetadataWriter.write(restore, to: fixture)
        #expect(try AudioMetadataWriter.infoDictionary(at: fixture)["title"] as? String == restore.title)
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

    private func makeM4A(at url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1
        ]
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
        buffer.frameLength = 4_410
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings)
            try file.write(from: buffer)
        }
    }

    private func m4aMediaData(at url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        var offset = 0
        while offset + 8 <= data.count {
            var atomSize = Int(data[offset]) << 24 | Int(data[offset + 1]) << 16
                | Int(data[offset + 2]) << 8 | Int(data[offset + 3])
            let atomType = String(data: data[(offset + 4)..<(offset + 8)], encoding: .ascii)
            var headerSize = 8
            if atomSize == 1 {
                guard offset + 16 <= data.count else { break }
                atomSize = data[(offset + 8)..<(offset + 16)].reduce(0) { ($0 << 8) | Int($1) }
                headerSize = 16
            } else if atomSize == 0 {
                atomSize = data.count - offset
            }
            guard atomSize >= headerSize, offset + atomSize <= data.count else { break }
            if atomType == "mdat" {
                return Data(data[(offset + headerSize)..<(offset + atomSize)])
            }
            offset += atomSize
        }
        throw MassiveMusicError.metadataWriteFailed("M4Aの音声領域を確認できません。")
    }

    private func makeID3v23(title: String, artworkPayload: Data, audioBytes: Data) -> Data {
        func frame(_ id: String, payload: Data) -> Data {
            var result = Data(id.utf8)
            let size = payload.count
            result.append(contentsOf: [UInt8(size >> 24), UInt8(size >> 16), UInt8(size >> 8), UInt8(size)])
            result.append(contentsOf: [0, 0])
            result.append(payload)
            return result
        }
        var titlePayload = Data([3])
        titlePayload.append(Data(title.utf8))
        var body = frame("TIT2", payload: titlePayload)
        body.append(frame("APIC", payload: artworkPayload))
        body.append(Data(repeating: 0, count: 128))
        var result = Data("ID3".utf8)
        result.append(contentsOf: [3, 0, 0])
        result.append(contentsOf: [UInt8((body.count >> 21) & 0x7F), UInt8((body.count >> 14) & 0x7F),
                                   UInt8((body.count >> 7) & 0x7F), UInt8(body.count & 0x7F)])
        result.append(body)
        result.append(audioBytes)
        return result
    }

    private func makeID3v22(title: String, artworkBytes: Data, audioBytes: Data) -> Data {
        func frame(_ id: String, payload: Data) -> Data {
            var result = Data(id.utf8)
            let size = payload.count
            result.append(contentsOf: [UInt8(size >> 16), UInt8(size >> 8), UInt8(size)])
            result.append(payload)
            return result
        }
        var titlePayload = Data([0])
        titlePayload.append(title.data(using: .isoLatin1) ?? Data())
        var artistPayload = Data([0])
        artistPayload.append(Data("The Rolling Stones".utf8))
        var albumPayload = Data([0])
        albumPayload.append(Data("Voodoo Lounge".utf8))
        var picturePayload = Data([0])
        picturePayload.append(Data("JPG".utf8))
        picturePayload.append(contentsOf: [3, 0])
        picturePayload.append(artworkBytes)
        var body = frame("TT2", payload: titlePayload)
        body.append(frame("TP1", payload: artistPayload))
        body.append(frame("TAL", payload: albumPayload))
        body.append(frame("PIC", payload: picturePayload))
        body.append(Data(repeating: 0, count: 64))
        var result = Data("ID3".utf8)
        result.append(contentsOf: [2, 0, 0])
        result.append(contentsOf: [UInt8((body.count >> 21) & 0x7F), UInt8((body.count >> 14) & 0x7F),
                                   UInt8((body.count >> 7) & 0x7F), UInt8(body.count & 0x7F)])
        result.append(body)
        result.append(audioBytes)
        return result
    }

    private func makeMalformedID3v24(audioBytes: Data) -> Data {
        var body = Data("TIT2".utf8)
        // This declares a 4,096-byte frame inside a much smaller tag body.
        body.append(contentsOf: [0, 0, 0x20, 0])
        body.append(contentsOf: [0, 0, 3])
        body.append(Data("Old".utf8))
        body.append(Data(repeating: 0, count: 64))
        var result = Data("ID3".utf8)
        result.append(contentsOf: [4, 0, 0])
        result.append(contentsOf: [UInt8((body.count >> 21) & 0x7F), UInt8((body.count >> 14) & 0x7F),
                                   UInt8((body.count >> 7) & 0x7F), UInt8(body.count & 0x7F)])
        result.append(body)
        result.append(audioBytes)
        return result
    }

    private func makeMPEG1Layer3Frames(count: Int) -> Data {
        // MPEG-1 Layer III, 128 kbps, 44.1 kHz. Each frame is 417 bytes.
        let header = Data([0xFF, 0xFB, 0x90, 0x00])
        var result = Data()
        for index in 0..<count {
            result.append(header)
            result.append(Data(repeating: UInt8(0x40 + index), count: 413))
        }
        return result
    }

    private func makeID3v24(title: String, artworkPayload: Data, audioBytes: Data) -> Data {
        func frame(_ id: String, payload: Data) -> Data {
            var result = Data(id.utf8)
            let size = payload.count
            result.append(contentsOf: [UInt8((size >> 21) & 0x7F), UInt8((size >> 14) & 0x7F),
                                       UInt8((size >> 7) & 0x7F), UInt8(size & 0x7F)])
            result.append(contentsOf: [0, 0])
            result.append(payload)
            return result
        }
        var titlePayload = Data([3])
        titlePayload.append(Data(title.utf8))
        var body = frame("TIT2", payload: titlePayload)
        body.append(frame("APIC", payload: artworkPayload))
        body.append(Data(repeating: 0, count: 128))
        var result = Data("ID3".utf8)
        result.append(contentsOf: [4, 0, 0])
        result.append(contentsOf: [UInt8((body.count >> 21) & 0x7F), UInt8((body.count >> 14) & 0x7F),
                                   UInt8((body.count >> 7) & 0x7F), UInt8(body.count & 0x7F)])
        result.append(body)
        result.append(audioBytes)
        return result
    }

    private func mp3AudioPayload(at url: URL) throws -> Data {
        let data = try Data(contentsOf: url)
        guard data.count >= 10, data.prefix(3) == Data("ID3".utf8) else { return data }
        let bodySize = data[6...9].reduce(0) { ($0 << 7) | Int($1 & 0x7F) }
        return Data(data.dropFirst(10 + bodySize))
    }
}

private extension Data {
    func containsSubsequence(_ needle: Data) -> Bool { range(of: needle) != nil }
}
