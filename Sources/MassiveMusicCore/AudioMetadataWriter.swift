import AudioToolbox
import Foundation

public enum AudioMetadataWriter {
    private static let supportedExtensions = ["mp3", "m4a", "wav"]

    /// Writes and verifies an app-local copy before changing the source. The final
    /// streaming write preserves the source inode, permissions, and extended attributes,
    /// and can succeed when a sandbox grant allows editing the file but not creating a
    /// new sibling in its parent directory.
    public static func write(
        _ edit: TrackMetadataEdit,
        to sourceURL: URL,
        repairingCorruptID3: Bool = false
    ) throws {
        let edit = edit.normalizingLeadingTitleSpaces()
        let ext = sourceURL.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else { throw MassiveMusicError.unsupportedAudioFormat(ext) }
        if edit.artworkData != nil, ext != "mp3" {
            throw MassiveMusicError.metadataWriteFailed("ジャケットのファイル書き込みは現在MP3に対応しています。元のファイルは変更していません。")
        }
        if edit.isCompilation, ext != "mp3" {
            throw MassiveMusicError.metadataWriteFailed("コンピレーションタグのファイル書き込みは現在MP3に対応しています。元のファイルは変更していません。")
        }
        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appending(path: "MassiveMusicMetadataWrites", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        let token = UUID().uuidString
        let backupURL = temporaryDirectory.appending(path: "\(token)-original.\(ext)")
        let workingURL = temporaryDirectory.appending(path: "\(token)-edited.\(ext)")
        defer {
            try? fileManager.removeItem(at: backupURL)
            try? fileManager.removeItem(at: workingURL)
        }

        try fileManager.copyItem(at: sourceURL, to: backupURL)
        try fileManager.copyItem(at: backupURL, to: workingURL)
        if ext == "wav" { try writeRIFFInfo(edit, at: workingURL) }
        else if ext == "mp3" {
            try writeID3(edit, at: workingURL, repairingCorruptID3: repairingCorruptID3)
        }
        else { try writeM4AInfo(edit, at: workingURL) }
        let workingValues = try infoDictionary(at: workingURL)
        guard metadataMatches(workingValues, edit: edit), try artworkMatches(edit, at: workingURL) else {
            throw MassiveMusicError.metadataWriteFailed(
                "書き込み後の検証に失敗しました（\(metadataMismatchDescription(workingValues, edit: edit))）。元のファイルは変更していません。"
            )
        }

        var sourceWasOpenedForWriting = false
        do {
            try copyContents(from: workingURL, toExistingFile: sourceURL) {
                sourceWasOpenedForWriting = true
            }
            guard metadataMatches(try infoDictionary(at: sourceURL), edit: edit), try artworkMatches(edit, at: sourceURL) else {
                throw MassiveMusicError.metadataWriteFailed("元ファイルへ反映した後の検証に失敗しました。")
            }
        } catch {
            // Opening the destination failed before it could be changed. Preserve
            // the original permission error so the app can request a fresh
            // read-write security-scoped bookmark instead of reporting a failed
            // rollback for a file that was never touched.
            guard sourceWasOpenedForWriting else { throw error }
            do {
                try copyContents(from: backupURL, toExistingFile: sourceURL)
            } catch let restoreError {
                throw MassiveMusicError.metadataWriteFailed(
                    "書き込みに失敗し、バックアップの復元にも失敗しました: \(restoreError.localizedDescription)"
                )
            }
            throw error
        }
    }

    public static func infoDictionary(at url: URL) throws -> [String: Any] {
        if url.pathExtension.lowercased() == "wav" { return try riffInfoDictionary(at: url) }
        if url.pathExtension.lowercased() == "mp3" { return try id3InfoDictionary(at: url) }
        if url.pathExtension.lowercased() == "m4a" {
            var readError: NSError?
            if let info = MassiveMusicReadM4AMetadata(url, &readError) { return info }
            throw MassiveMusicError.metadataWriteFailed(
                readError?.localizedDescription ?? "M4Aメタデータを読み込めませんでした。"
            )
        }
        var file: AudioFileID?
        let openStatus = AudioFileOpenURL(url as CFURL, .readPermission, 0, &file)
        guard openStatus == noErr, let file else { throw statusError(openStatus) }
        defer { AudioFileClose(file) }

        var size = UInt32(MemoryLayout<CFDictionary?>.size)
        var dictionary: Unmanaged<CFDictionary>?
        let status = AudioFileGetProperty(file, kAudioFilePropertyInfoDictionary, &size, &dictionary)
        guard status == noErr, let dictionary else { throw statusError(status) }
        return dictionary.takeRetainedValue() as NSDictionary as? [String: Any] ?? [:]
    }

    /// M4A exposes its AudioToolbox info dictionary as read-only (`prm?`).
    /// AVMutableMovie replaces only the `moov` header and preserves the `mdat`
    /// audio payload byte-for-byte.
    private static func writeM4AInfo(_ edit: TrackMetadataEdit, at url: URL) throws {
        var info: [String: Any] = [
            "title": edit.title,
            "artist": edit.artist,
            "album": edit.album,
            "album artist": edit.albumArtist,
            "genre": edit.genre
        ]
        if let trackNumber = edit.trackNumber { info["track number"] = trackNumber }
        if let discNumber = edit.discNumber { info["disc number"] = discNumber }
        var writeError: NSError?
        guard MassiveMusicWriteM4AHeader(url, info, &writeError) else {
            throw MassiveMusicError.metadataWriteFailed(
                writeError?.localizedDescription ?? "M4Aヘッダーを書き込めませんでした。"
            )
        }
    }

    /// AudioToolbox exposes the MP3 info dictionary as read-only for many ID3v2.3
    /// files (`kAudioFileUnsupportedPropertyError`). Update only the requested text
    /// frames directly and preserve every other frame, including embedded artwork.
    private static func writeID3(
        _ edit: TrackMetadataEdit,
        at url: URL,
        repairingCorruptID3: Bool
    ) throws {
        let input = try Data(contentsOf: url, options: .mappedIfSafe)
        let existing: ParsedID3
        let rebuiltDamagedTag: Bool
        if repairingCorruptID3 {
            // The user explicitly accepted a rebuild after a normal parse
            // failed. Do not feed the damaged frame table through the normal
            // parser a second time.
            existing = try repairableID3Layout(input)
            rebuiltDamagedTag = true
        } else {
            existing = try parseID3(input)
            rebuiltDamagedTag = false
        }
        guard repairingCorruptID3 || existing.majorVersion == nil || existing.majorVersion == 3 || existing.majorVersion == 4 else {
            throw MassiveMusicError.metadataWriteFailed("ID3v2.2以前のMP3タグは、安全な変換確認後に修復できます。")
        }

        var replacedIDs: Set<String> = ["TIT2", "TPE1", "TALB", "TPE2", "TCON", "TRCK", "TPOS", "TCMP"]
        if edit.artworkData != nil { replacedIDs.insert("APIC") }
        var frames = existing.frames.filter { !replacedIDs.contains($0.id) }.map { frame in
            // ID3v2.4 frame sizes are synchsafe while ID3v2.3 frame sizes are
            // ordinary big-endian integers. Re-encode preserved frame headers
            // when the enclosing tag is converted to v2.3; copying raw v2.4
            // bytes makes large artwork frames appear to exceed the tag.
            existing.majorVersion == 4
                ? id3v23Frame(id: frame.id, payload: frame.payload)
                : frame.rawData
        }
        let values: [(String, String)] = [
            ("TIT2", edit.title), ("TPE1", edit.artist), ("TALB", edit.album),
            ("TPE2", edit.albumArtist), ("TCON", edit.genre),
            ("TRCK", edit.trackNumber.map(String.init) ?? ""),
            ("TPOS", edit.discNumber.map(String.init) ?? "")
        ]
        for (id, value) in values where !value.isEmpty { frames.append(id3v23TextFrame(id: id, value: value)) }
        if edit.isCompilation { frames.append(id3v23TextFrame(id: "TCMP", value: "1")) }
        if let artworkData = edit.artworkData {
            frames.append(try id3v23ArtworkFrame(artworkData))
        }

        var body = frames.reduce(into: Data()) { $0.append($1) }
        // Reuse the old tag allocation when possible so a small edit does not move
        // millions of audio bytes or unexpectedly grow the file.
        // Do not carry a damaged tag's unusually large allocation forward. A
        // modest clean padding area is enough for later edits and avoids
        // preserving any unreadable bytes from the old tag.
        let bodySize = rebuiltDamagedTag ? max(body.count, 1_024) : max(body.count, existing.bodySize)
        if body.count < bodySize { body.append(Data(repeating: 0, count: bodySize - body.count)) }
        var output = Data("ID3".utf8)
        output.append(contentsOf: [3, 0, 0])
        output.append(contentsOf: synchsafeBytes(bodySize))
        output.append(body)
        output.append(input[existing.audioOffset...])
        try output.write(to: url, options: .atomic)
    }

    /// Returns only the validated tag allocation and audio boundary. Repair is
    /// deliberately explicit because unreadable ID3 frames cannot be preserved.
    /// The MPEG payload is retained byte-for-byte and receives a fresh ID3v2.3 tag.
    private static func repairableID3Layout(_ data: Data) throws -> ParsedID3 {
        guard data.count >= 12, data.prefix(3) == Data("ID3".utf8) else {
            throw MassiveMusicError.metadataWriteFailed("修復できるID3v2タグが見つかりません。")
        }
        let version = data[3]
        guard version <= 4 else {
            throw MassiveMusicError.metadataWriteFailed("このID3バージョンは修復できません。")
        }
        guard data[6...9].allSatisfy({ $0 & 0x80 == 0 }) else {
            throw MassiveMusicError.metadataWriteFailed("ID3タグの音声開始位置を安全に判定できません。元のファイルは変更していません。")
        }
        let bodySize = synchsafeInteger(data[6...9])
        let declaredAudioOffset = 10 + bodySize
        let audioOffset: Int
        if hasMPEGSync(data, at: declaredAudioOffset) {
            audioOffset = declaredAudioOffset
        } else if let recoveredOffset = validatedMPEGAudioOffset(in: data, after: 10) {
            // Some old taggers wrote a plausible but incorrect ID3 allocation.
            // Accept a recovered boundary only after three structurally valid,
            // consecutive MPEG Layer III frames. This avoids treating 0xFF bytes
            // in artwork or damaged tag payloads as the start of the audio stream.
            audioOffset = recoveredOffset
        } else {
            throw MassiveMusicError.metadataWriteFailed("MP3音声の開始位置を確認できないため修復を中止しました。元のファイルは変更していません。")
        }
        let frames: [ID3Frame]
        if version == 2 {
            // Preserve readable v2.2 frames (notably artwork), but an explicit
            // repair must still be able to rebuild a tag whose frame table is
            // damaged. In that case the database-backed edit supplies the
            // primary fields and only the verified MPEG payload is retained.
            frames = (try? convertedID3v22Frames(data, audioOffset: audioOffset)) ?? []
        } else {
            // v2.0/v2.1 did not standardize a frame layout that can be preserved
            // safely. The database-backed edit supplies the primary fields while
            // the MPEG payload remains byte-identical.
            frames = []
        }
        return ParsedID3(majorVersion: version, bodySize: bodySize, audioOffset: audioOffset, frames: frames)
    }

    private struct MPEGFrameLayout {
        let length: Int
        let version: Int
        let layer: Int
        let sampleRate: Int
    }

    private static func hasMPEGSync(_ data: Data, at offset: Int) -> Bool {
        guard offset >= 0, offset + 1 < data.count else { return false }
        return data[offset] == 0xFF && data[offset + 1] & 0xE0 == 0xE0
    }

    private static func validatedMPEGAudioOffset(in data: Data, after start: Int) -> Int? {
        guard data.count >= 12 else { return nil }
        let upperBound = data.count - 4
        var candidate = max(0, start)
        while candidate <= upperBound {
            guard hasMPEGSync(data, at: candidate),
                  let first = mpegFrameLayout(in: data, at: candidate) else {
                candidate += 1
                continue
            }
            if hasValidatedMPEGFrames(in: data, at: candidate, first: first) { return candidate }
            candidate += 1
        }
        return nil
    }

    private static func hasValidatedMPEGFrames(
        in data: Data, at offset: Int, first: MPEGFrameLayout
    ) -> Bool {
        var nextOffset = offset + first.length
        var validFrames = 1
        while validFrames < 3,
              let next = mpegFrameLayout(in: data, at: nextOffset),
              next.version == first.version,
              next.layer == first.layer,
              next.sampleRate == first.sampleRate {
            validFrames += 1
            nextOffset += next.length
        }
        return validFrames == 3
    }

    private static func mpegFrameLayout(in data: Data, at offset: Int) -> MPEGFrameLayout? {
        guard offset >= 0, offset + 3 < data.count else { return nil }
        let header = UInt32(data[offset]) << 24
            | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8
            | UInt32(data[offset + 3])
        guard header & 0xFFE0_0000 == 0xFFE0_0000 else { return nil }
        let version = Int((header >> 19) & 0x3)
        let layer = Int((header >> 17) & 0x3)
        let bitrateIndex = Int((header >> 12) & 0xF)
        let sampleRateIndex = Int((header >> 10) & 0x3)
        let padding = Int((header >> 9) & 0x1)
        guard version != 1, layer == 1,
              (1...14).contains(bitrateIndex), sampleRateIndex < 3 else { return nil }

        let mpeg1Bitrates = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
        let mpeg2Bitrates = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160]
        let sampleRates: [Int]
        switch version {
        case 3: sampleRates = [44_100, 48_000, 32_000]
        case 2: sampleRates = [22_050, 24_000, 16_000]
        default: sampleRates = [11_025, 12_000, 8_000]
        }
        let bitrate = (version == 3 ? mpeg1Bitrates : mpeg2Bitrates)[bitrateIndex] * 1_000
        let sampleRate = sampleRates[sampleRateIndex]
        let coefficient = version == 3 ? 144 : 72
        let length = coefficient * bitrate / sampleRate + padding
        guard length >= 4, offset + length <= data.count else { return nil }
        return MPEGFrameLayout(length: length, version: version, layer: layer, sampleRate: sampleRate)
    }

    /// Converts recoverable ID3v2.2 frames to v2.3. Unknown three-character
    /// frames are intentionally omitted because copying them with a fabricated
    /// identifier would create an invalid tag.
    private static func convertedID3v22Frames(_ data: Data, audioOffset: Int) throws -> [ID3Frame] {
        guard data[5] & 0xC0 == 0 else {
            throw MassiveMusicError.metadataWriteFailed("圧縮または非同期化されたID3v2.2タグは安全に変換できません。")
        }
        let identifiers = [
            "TT2": "TIT2", "TP1": "TPE1", "TAL": "TALB", "TP2": "TPE2",
            "TCO": "TCON", "TRK": "TRCK", "TPA": "TPOS"
        ]
        var frames: [ID3Frame] = []
        var offset = 10
        while offset + 6 <= audioOffset {
            let identifierBytes = data[offset..<(offset + 3)]
            if identifierBytes.allSatisfy({ $0 == 0 }) { break }
            guard let oldID = String(data: identifierBytes, encoding: .ascii), oldID.count == 3 else {
                throw MassiveMusicError.metadataWriteFailed("ID3v2.2フレーム識別子が破損しています。")
            }
            let size = bigEndianInteger(data[(offset + 3)..<(offset + 6)])
            let end = offset + 6 + size
            guard size >= 0, end <= audioOffset else {
                throw MassiveMusicError.metadataWriteFailed("ID3v2.2フレームが破損しています。")
            }
            let oldPayload = Data(data[(offset + 6)..<end])
            if oldID == "PIC" {
                let payload = try convertedID3v22PicturePayload(oldPayload)
                let raw = id3v23Frame(id: "APIC", payload: payload)
                frames.append(ID3Frame(id: "APIC", payload: payload, rawData: raw))
            } else if let newID = identifiers[oldID] {
                let raw = id3v23Frame(id: newID, payload: oldPayload)
                frames.append(ID3Frame(id: newID, payload: oldPayload, rawData: raw))
            }
            offset = end
        }
        return frames
    }

    private static func convertedID3v22PicturePayload(_ payload: Data) throws -> Data {
        guard payload.count >= 5 else {
            throw MassiveMusicError.metadataWriteFailed("ID3v2.2の埋め込み画像が破損しています。")
        }
        let format = String(data: payload[1..<4], encoding: .ascii)?.uppercased()
        let mimeType: String
        switch format {
        case "JPG": mimeType = "image/jpeg"
        case "PNG": mimeType = "image/png"
        default: mimeType = "application/octet-stream"
        }
        var converted = Data([payload[0]])
        converted.append(Data(mimeType.utf8))
        converted.append(0)
        converted.append(payload[4...])
        return converted
    }

    private struct ID3Frame {
        let id: String
        let payload: Data
        let rawData: Data
    }

    private struct ParsedID3 {
        let majorVersion: UInt8?
        let bodySize: Int
        let audioOffset: Int
        let frames: [ID3Frame]
    }

    private static func parseID3(_ data: Data) throws -> ParsedID3 {
        guard data.count >= 10, data.prefix(3) == Data("ID3".utf8) else {
            return ParsedID3(majorVersion: nil, bodySize: 0, audioOffset: 0, frames: [])
        }
        let version = data[3]
        guard version == 3 || version == 4 else {
            return ParsedID3(majorVersion: version, bodySize: 0, audioOffset: 0, frames: [])
        }
        guard data[6...9].allSatisfy({ $0 & 0x80 == 0 }) else {
            throw MassiveMusicError.metadataWriteFailed("ID3タグのサイズが破損しています。")
        }
        let bodySize = synchsafeInteger(data[6...9])
        let audioOffset = 10 + bodySize
        guard audioOffset <= data.count else { throw MassiveMusicError.metadataWriteFailed("ID3タグが途中で切れています。") }
        // Extended headers and whole-tag unsynchronisation require byte-level
        // rewriting that cannot safely preserve unknown frames.
        guard data[5] & 0xC0 == 0 else {
            throw MassiveMusicError.metadataWriteFailed("拡張ヘッダー付きID3タグには現在対応していません。")
        }

        var frames: [ID3Frame] = []
        var offset = 10
        while offset + 10 <= audioOffset {
            let identifierBytes = data[offset..<(offset + 4)]
            if identifierBytes.allSatisfy({ $0 == 0 }) { break }
            guard let id = String(data: identifierBytes, encoding: .ascii),
                  id.count == 4,
                  id.utf8.allSatisfy({ ($0 >= 65 && $0 <= 90) || ($0 >= 48 && $0 <= 57) }) else { break }
            let sizeBytes = data[(offset + 4)..<(offset + 8)]
            let size = version == 4 ? synchsafeInteger(sizeBytes) : bigEndianInteger(sizeBytes)
            let end = offset + 10 + size
            guard size >= 0, end <= audioOffset else { throw MassiveMusicError.metadataWriteFailed("ID3フレームが破損しています。") }
            frames.append(ID3Frame(
                id: id,
                payload: Data(data[(offset + 10)..<end]),
                rawData: Data(data[offset..<end])
            ))
            offset = end
        }
        return ParsedID3(majorVersion: version, bodySize: bodySize, audioOffset: audioOffset, frames: frames)
    }

    private static func id3InfoDictionary(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let parsed = try parseID3(data)
        let names = ["TIT2": "title", "TPE1": "artist", "TALB": "album", "TPE2": "album artist",
                     "TCON": "genre", "TRCK": "track number", "TPOS": "disc number", "TCMP": "compilation"]
        var result: [String: Any] = [:]
        for frame in parsed.frames {
            guard let key = names[frame.id], let value = decodeID3Text(frame.payload) else { continue }
            if frame.id == "TRCK" || frame.id == "TPOS" {
                result[key] = value.components(separatedBy: "/").first ?? value
            } else {
                result[key] = value
            }
        }
        return result
    }

    private static func id3v23TextFrame(id: String, value: String) -> Data {
        var payload: Data
        if let latin1 = value.data(using: .isoLatin1, allowLossyConversion: false) {
            payload = Data([0])
            payload.append(latin1)
        } else {
            payload = Data([1, 0xFF, 0xFE])
            payload.append(value.data(using: .utf16LittleEndian) ?? Data())
        }
        return id3v23Frame(id: id, payload: payload)
    }

    private static func id3v23ArtworkFrame(_ artworkData: Data) throws -> Data {
        let mimeType: String
        if artworkData.starts(with: [0xFF, 0xD8, 0xFF]) {
            mimeType = "image/jpeg"
        } else if artworkData.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            mimeType = "image/png"
        } else {
            throw MassiveMusicError.metadataWriteFailed("ジャケット画像はJPEGまたはPNGを選択してください。")
        }
        var payload = Data([0])
        payload.append(Data(mimeType.utf8))
        payload.append(0)
        payload.append(3) // Front cover
        payload.append(0) // Empty ISO-8859-1 description
        payload.append(artworkData)
        return id3v23Frame(id: "APIC", payload: payload)
    }

    private static func id3v23Frame(id: String, payload: Data) -> Data {
        var frame = Data(id.utf8)
        frame.append(contentsOf: bigEndianBytes(payload.count))
        frame.append(contentsOf: [0, 0])
        frame.append(payload)
        return frame
    }

    private static func decodeID3Text(_ payload: Data) -> String? {
        guard let encoding = payload.first else { return nil }
        let value = Data(payload.dropFirst())
        let decoded: String?
        switch encoding {
        case 0: decoded = String(data: value, encoding: .isoLatin1)
        case 1:
            if value.starts(with: [0xFF, 0xFE]) {
                decoded = String(data: value.dropFirst(2), encoding: .utf16LittleEndian)
            } else if value.starts(with: [0xFE, 0xFF]) {
                decoded = String(data: value.dropFirst(2), encoding: .utf16BigEndian)
            } else {
                decoded = String(data: value, encoding: .utf16)
            }
        case 2: decoded = String(data: value, encoding: .utf16BigEndian)
        case 3: decoded = String(data: value, encoding: .utf8)
        default: decoded = nil
        }
        return decoded?.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
    }

    private static func synchsafeInteger(_ bytes: Data.SubSequence) -> Int {
        bytes.reduce(0) { ($0 << 7) | Int($1 & 0x7F) }
    }

    private static func bigEndianInteger(_ bytes: Data.SubSequence) -> Int {
        bytes.reduce(0) { ($0 << 8) | Int($1) }
    }

    private static func synchsafeBytes(_ value: Int) -> [UInt8] {
        [UInt8((value >> 21) & 0x7F), UInt8((value >> 14) & 0x7F),
         UInt8((value >> 7) & 0x7F), UInt8(value & 0x7F)]
    }

    private static func bigEndianBytes(_ value: Int) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
         UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private static func writeRIFFInfo(_ edit: TrackMetadataEdit, at url: URL) throws {
        let input = try Data(contentsOf: url, options: .mappedIfSafe)
        guard input.count >= 12,
              String(data: input[0..<4], encoding: .ascii) == "RIFF",
              String(data: input[8..<12], encoding: .ascii) == "WAVE" else {
            throw MassiveMusicError.metadataWriteFailed("標準RIFF/WAVEファイルではありません。")
        }

        var output = Data(input[0..<12])
        var offset = 12
        while offset + 8 <= input.count {
            let size = Int(readUInt32LE(input, at: offset + 4))
            let paddedSize = size + (size & 1)
            let end = offset + 8 + paddedSize
            guard end <= input.count else {
                throw MassiveMusicError.metadataWriteFailed("WAVチャンクが破損しています。")
            }
            let isInfoList = String(data: input[offset..<(offset + 4)], encoding: .ascii) == "LIST"
                && size >= 4
                && String(data: input[(offset + 8)..<(offset + 12)], encoding: .ascii) == "INFO"
            if !isInfoList { output.append(input[offset..<end]) }
            offset = end
        }
        guard offset == input.count else {
            throw MassiveMusicError.metadataWriteFailed("WAV末尾の構造を確認できません。")
        }

        var list = Data("INFO".utf8)
        appendRIFFField("INAM", value: edit.title, to: &list)
        appendRIFFField("IART", value: edit.artist, to: &list)
        appendRIFFField("IPRD", value: edit.album, to: &list)
        appendRIFFField("IAAR", value: edit.albumArtist, to: &list)
        appendRIFFField("IGNR", value: edit.genre, to: &list)
        appendRIFFField("ITRK", value: edit.trackNumber.map(String.init) ?? "", to: &list)
        appendRIFFField("IPRT", value: edit.discNumber.map(String.init) ?? "", to: &list)
        output.append(Data("LIST".utf8))
        appendUInt32LE(UInt32(list.count), to: &output)
        output.append(list)
        if list.count & 1 == 1 { output.append(0) }
        guard output.count - 8 <= Int(UInt32.max) else {
            throw MassiveMusicError.metadataWriteFailed("4GBを超えるRIFF/WAVには現在対応していません。")
        }
        var riffSize = UInt32(output.count - 8).littleEndian
        withUnsafeBytes(of: &riffSize) { output.replaceSubrange(4..<8, with: $0) }
        try output.write(to: url, options: .atomic)
    }

    private static func riffInfoDictionary(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 12,
              String(data: data[0..<4], encoding: .ascii) == "RIFF",
              String(data: data[8..<12], encoding: .ascii) == "WAVE" else {
            throw MassiveMusicError.metadataWriteFailed("標準RIFF/WAVEファイルではありません。")
        }
        let names = ["INAM": "title", "IART": "artist", "IPRD": "album", "IAAR": "album artist",
                     "IGNR": "genre", "ITRK": "track number", "IPRT": "disc number"]
        var result: [String: Any] = [:]
        var offset = 12
        while offset + 8 <= data.count {
            let size = Int(readUInt32LE(data, at: offset + 4))
            let end = offset + 8 + size + (size & 1)
            guard end <= data.count else { throw MassiveMusicError.metadataWriteFailed("WAVチャンクが破損しています。") }
            if String(data: data[offset..<(offset + 4)], encoding: .ascii) == "LIST", size >= 4,
               String(data: data[(offset + 8)..<(offset + 12)], encoding: .ascii) == "INFO" {
                var itemOffset = offset + 12
                let listEnd = offset + 8 + size
                while itemOffset + 8 <= listEnd {
                    let id = String(data: data[itemOffset..<(itemOffset + 4)], encoding: .ascii) ?? ""
                    let itemSize = Int(readUInt32LE(data, at: itemOffset + 4))
                    let valueStart = itemOffset + 8
                    guard valueStart + itemSize <= listEnd else { break }
                    if let key = names[id] {
                        let bytes = data[valueStart..<(valueStart + itemSize)].prefix { $0 != 0 }
                        result[key] = String(data: bytes, encoding: .utf8) ?? ""
                    }
                    itemOffset = valueStart + itemSize + (itemSize & 1)
                }
            }
            offset = end
        }
        return result
    }

    private static func appendRIFFField(_ id: String, value: String, to data: inout Data) {
        guard !value.isEmpty else { return }
        var valueData = Data(value.utf8)
        valueData.append(0)
        data.append(Data(id.utf8))
        appendUInt32LE(UInt32(valueData.count), to: &data)
        data.append(valueData)
        if valueData.count & 1 == 1 { data.append(0) }
    }

    private static func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }

    private static func normalized(_ value: Any?) -> String {
        (value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func metadataMatches(_ values: [String: Any], edit: TrackMetadataEdit) -> Bool {
        normalized(values["title"]) == normalized(edit.title)
            && normalized(values["artist"]) == normalized(edit.artist)
            && normalized(values["album"]) == normalized(edit.album)
            && normalized(values["track number"]) == normalized(edit.trackNumber.map(String.init))
            && normalized(values["disc number"]) == normalized(edit.discNumber.map(String.init))
            && compilationValue(values["compilation"]) == edit.isCompilation
    }

    private static func compilationValue(_ value: Any?) -> Bool {
        if let number = value as? NSNumber { return number.boolValue }
        let text = normalized(value).lowercased()
        return text == "1" || text == "true" || text == "yes"
    }

    private static func artworkMatches(_ edit: TrackMetadataEdit, at url: URL) throws -> Bool {
        guard let expected = edit.artworkData else { return true }
        guard url.pathExtension.lowercased() == "mp3" else { return false }
        let parsed = try parseID3(Data(contentsOf: url, options: .mappedIfSafe))
        return parsed.frames.contains { frame in
            frame.id == "APIC" && frame.payload.count >= expected.count
                && frame.payload.suffix(expected.count) == expected
        }
    }

    private static func metadataMismatchDescription(_ values: [String: Any], edit: TrackMetadataEdit) -> String {
        let expected: [(String, String)] = [
            ("title", normalized(edit.title)), ("artist", normalized(edit.artist)),
            ("album", normalized(edit.album)), ("track number", normalized(edit.trackNumber.map(String.init))),
            ("disc number", normalized(edit.discNumber.map(String.init)))
        ]
        return expected.compactMap { key, value in
            let actual = normalized(values[key])
            return actual == value ? nil : "\(key): expected=\(value.debugDescription), actual=\(actual.debugDescription)"
        }.joined(separator: ", ")
    }

    private static func copyContents(
        from source: URL,
        toExistingFile destination: URL,
        destinationWasOpened: () -> Void = {}
    ) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let output = try FileHandle(forWritingTo: destination)
        destinationWasOpened()
        defer { try? output.close() }
        try output.truncate(atOffset: 0)
        while let data = try input.read(upToCount: 1_048_576), !data.isEmpty {
            try output.write(contentsOf: data)
        }
        try output.synchronize()
    }

    private static func statusError(_ status: OSStatus) -> MassiveMusicError {
        let characters = [24, 16, 8, 0].map { Character(UnicodeScalar(UInt8((UInt32(bitPattern: status) >> $0) & 0xff))) }
        let code = String(characters).allSatisfy(\.isASCII) ? String(characters) : String(status)
        return .metadataWriteFailed("AudioToolbox error \(code)")
    }
}
