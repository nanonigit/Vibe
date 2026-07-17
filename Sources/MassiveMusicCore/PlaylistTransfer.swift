import Foundation

public enum PlaylistTransfer {
    public static func exportM3U8(
        playlistID: Int64,
        database: LibraryDatabase,
        destination: URL,
        progress: (@Sendable (Int) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) throws {
        FileManager.default.createFile(atPath: destination.path, contents: Data("#EXTM3U\n".utf8))
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        try handle.seekToEnd()
        var offset = 0
        while isCancelled?() != true {
            let page = try database.playlistTracks(playlistID: playlistID, offset: offset, limit: 1_000)
            if page.tracks.isEmpty { break }
            var chunk = ""
            chunk.reserveCapacity(page.tracks.count * 100)
            for track in page.tracks {
                guard let root = try database.scanRoot(id: track.rootID) else { continue }
                let path = URL(filePath: root.lastKnownPath).appending(path: track.relativePath).path
                chunk += "#EXTINF:\(Int(track.duration)),\(track.artist) - \(track.title)\n"
                chunk += path + "\n"
            }
            try handle.write(contentsOf: Data(chunk.utf8))
            offset += page.tracks.count
            progress?(offset)
            if !page.hasNext { break }
        }
    }

    public static func importM3U(
        source: URL,
        playlistID: Int64,
        database: LibraryDatabase,
        progress: (@Sendable (Int) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) async throws -> Int {
        let handle = try FileHandle(forReadingFrom: source)
        defer { try? handle.close() }
        var chunk: [Int64] = []
        chunk.reserveCapacity(LibraryDatabase.playlistCommitSize)
        var total = 0
        for try await line in handle.bytes.lines {
            if isCancelled?() == true { break }
            let path = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, !path.hasPrefix("#") else { continue }
            if let trackID = try database.trackID(relativeOrAbsolutePath: path) { chunk.append(trackID) }
            if chunk.count == LibraryDatabase.playlistCommitSize {
                total += try database.addTracks(chunk, toPlaylist: playlistID)
                chunk.removeAll(keepingCapacity: true)
                progress?(total)
            }
        }
        if !chunk.isEmpty, isCancelled?() != true {
            total += try database.addTracks(chunk, toPlaylist: playlistID)
            progress?(total)
        }
        return total
    }
}

