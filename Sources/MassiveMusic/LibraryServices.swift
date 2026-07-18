import AppKit
import Foundation
import MassiveMusicCore

struct EnrichedTrackInfo: Sendable {
    let lyrics: CachedLyrics?
    let artworkURL: URL?
    let wikipediaURL: URL?
    let detectedGenre: String?
}

actor TrackFileCoordinator {
    private let database: LibraryDatabase
    private let fileManager = FileManager.default

    init(database: LibraryDatabase) { self.database = database }

    func updateMetadata(
        track: Track,
        edit: TrackMetadataEdit,
        authorizedRoot: SecurityScopedRoot? = nil,
        repairingCorruptID3: Bool = false
    ) async throws {
        let edit = edit.normalizingLeadingTitleSpaces()
        let (scope, sourceURL) = try scopedSource(for: track, authorizedRoot: authorizedRoot)
        try scope.withAccess { _ in
            guard fileManager.fileExists(atPath: sourceURL.path) else { throw MassiveMusicError.trackUnavailable }
            try AudioMetadataWriter.write(edit, to: sourceURL, repairingCorruptID3: repairingCorruptID3)
            let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            try database.updateTrackMetadata(
                id: track.id,
                edit: edit,
                fileSize: Int64(values.fileSize ?? Int(track.fileSize)),
                modifiedAt: values.contentModificationDate ?? Date()
            )
        }
        if edit.artworkData != nil { await ArtworkCache.shared.invalidate(trackID: track.id) }
    }

    func removeFromLibrary(track: Track) throws {
        _ = try database.removeTrackFromLibrary(id: track.id, fileWasTrashed: false)
    }

    func moveFileToTrash(track: Track, authorizedRoot: SecurityScopedRoot? = nil) throws {
        let (scope, sourceURL) = try scopedSource(for: track, authorizedRoot: authorizedRoot)
        try scope.withAccess { _ in
            guard fileManager.fileExists(atPath: sourceURL.path) else { throw MassiveMusicError.trackUnavailable }
            var resultingURL: NSURL?
            try fileManager.trashItem(at: sourceURL, resultingItemURL: &resultingURL)
            _ = try database.removeTrackFromLibrary(id: track.id, fileWasTrashed: true)
        }
    }

    private func scopedSource(for track: Track, authorizedRoot: SecurityScopedRoot?) throws -> (SecurityScopedRoot, URL) {
        let scope: SecurityScopedRoot
        if let authorizedRoot {
            scope = authorizedRoot
        } else {
            guard let root = try database.scanRoot(id: track.rootID) else { throw MassiveMusicError.trackUnavailable }
            scope = try SecurityScopedRoot.resolve(bookmark: root.bookmark)
        }
        let rootURL = scope.url.standardizedFileURL
        let sourceURL = rootURL.appending(path: track.relativePath).standardizedFileURL
        let prefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard sourceURL.path.hasPrefix(prefix) else { throw MassiveMusicError.trackUnavailable }
        return (scope, sourceURL)
    }
}

actor StorageCoordinator {
    private let database: LibraryDatabase
    private let fileManager = FileManager.default
    private let inbox: URL

    init(database: LibraryDatabase) {
        self.database = database
        let support = (try? LibraryDatabase.applicationSupportURL().deletingLastPathComponent())
            ?? FileManager.default.temporaryDirectory.appending(path: "MassiveMusic")
        inbox = support.appending(path: "Inbox", directoryHint: .isDirectory)
        try? fileManager.createDirectory(at: inbox, withIntermediateDirectories: true)
    }

    func stage(
        _ sources: [URL],
        convertFlac: Bool = true,
        progress: (@Sendable (Int, Int, Double) -> Void)? = nil
    ) async throws -> [PendingImport] {
        var stagedItems: [PendingImport] = []
        for (index, source) in sources.enumerated() {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            
            let isFlac = source.pathExtension.lowercased() == "flac"
            let targetFilename = (isFlac && convertFlac) ? source.deletingPathExtension().appendingPathExtension("mp3").lastPathComponent : source.lastPathComponent
            let destination = uniqueURL(for: targetFilename, in: inbox)
            
            if isFlac && convertFlac {
                try await convertFlacToMp3(source: source, destination: destination) { fileProgress in
                    progress?(index + 1, sources.count, fileProgress)
                }
            } else {
                try fileManager.copyItem(at: source, to: destination)
                progress?(index + 1, sources.count, 1.0)
            }
            let id = try database.addPendingImport(localPath: destination.path, filename: destination.lastPathComponent)
            if let item = try database.pendingImport(id: id) {
                stagedItems.append(item)
            }
        }
        return stagedItems
    }

    private func convertFlacToMp3(source: URL, destination: URL, progress: (@Sendable (Double) -> Void)? = nil) async throws {
        let duration = await AudioMetadataReader.read(url: source).duration
        let totalDuration = duration > 0 ? duration : 180.0
        
        let process = Process()
        process.executableURL = URL(filePath: "/opt/homebrew/bin/ffmpeg")
        process.arguments = [
            "-nostdin",
            "-i", source.path,
            "-codec:a", "libmp3lame",
            "-qscale:a", "0",
            "-y",
            destination.path
        ]
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        try process.run()
        
        let fileHandle = errorPipe.fileHandleForReading
        
        let bufferSize = 1024
        var remainingData = Data()
        
        while process.isRunning {
            if let data = try? fileHandle.read(upToCount: bufferSize), !data.isEmpty {
                remainingData.append(data)
                while let lineRange = remainingData.firstRange(of: Data([0x0A])) {
                    let lineData = remainingData.subdata(in: remainingData.startIndex..<lineRange.lowerBound)
                    remainingData.removeSubrange(remainingData.startIndex..<lineRange.upperBound)
                    
                    if let line = String(data: lineData, encoding: .utf8) {
                        if let timeRange = line.range(of: "time=") {
                            let timePart = line[timeRange.upperBound...]
                            let tokens = timePart.split(separator: " ")
                            if let firstToken = tokens.first {
                                let timeStr = String(firstToken)
                                let parts = timeStr.split(separator: ":")
                                if parts.count == 3,
                                   let hours = Double(parts[0]),
                                   let minutes = Double(parts[1]),
                                   let seconds = Double(parts[2]) {
                                    let currentTime = hours * 3600.0 + minutes * 60.0 + seconds
                                    let pct = min(1.0, max(0.0, currentTime / totalDuration))
                                    progress?(pct)
                                }
                            }
                        }
                    }
                }
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            let errorData = fileHandle.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown ffmpeg error"
            throw MassiveMusicError.metadataWriteFailed("FLAC to MP3 conversion failed: \(errorMessage)")
        }
        
        progress?(1.0)
    }

    func addDestination(_ url: URL) throws -> [StorageDestination] {
        let scoped = try SecurityScopedRoot.create(for: url)
        _ = try database.addStorageDestination(name: url.lastPathComponent, path: url.path, bookmark: scoped.bookmark)
        _ = try? database.addScanRoot(displayName: url.lastPathComponent, bookmark: scoped.bookmark, volumeUUID: nil, path: url.path)
        return try database.storageDestinations()
    }

    func move(_ item: PendingImport, to destination: StorageDestination) throws {
        let root = try SecurityScopedRoot.resolve(bookmark: destination.bookmark)
        guard fileManager.fileExists(atPath: root.url.path) else { throw MassiveMusicError.scanRootUnavailable }
        let started = root.url.startAccessingSecurityScopedResource()
        defer { if started { root.url.stopAccessingSecurityScopedResource() } }
        let source = URL(filePath: item.localPath)
        let target = uniqueURL(for: item.filename, in: root.url)
        try fileManager.moveItem(at: source, to: target)
        try database.updatePendingImport(id: item.id, state: .moved, localPath: target.path)
    }

    private func uniqueURL(for filename: String, in directory: URL) -> URL {
        let original = directory.appending(path: filename)
        guard fileManager.fileExists(atPath: original.path) else { return original }
        let base = original.deletingPathExtension().lastPathComponent
        let ext = original.pathExtension
        for index in 2...10_000 {
            let name = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            let candidate = directory.appending(path: name)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        return directory.appending(path: "\(UUID().uuidString)-\(filename)")
    }
}

actor OfflineCacheManager {
    private let database: LibraryDatabase
    private let fileManager = FileManager.default
    private let directory: URL

    nonisolated static func cacheDirectoryURL() -> URL {
        let support = (try? LibraryDatabase.applicationSupportURL().deletingLastPathComponent())
            ?? FileManager.default.temporaryDirectory.appending(path: "MassiveMusic")
        return support.appending(path: "OfflineCache", directoryHint: .isDirectory)
    }

    init(database: LibraryDatabase) {
        self.database = database
        directory = Self.cacheDirectoryURL()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func playableURL(for track: Track, sourceURL: URL) throws -> URL {
        if let cached = try cachedPlayableURL(for: track) { return cached }
        let enabled = (try database.setting(forKey: "cache.enabled") ?? "true") == "true"
        guard enabled else { return sourceURL }
        let target = directory.appending(path: "\(track.id).\(track.format.lowercased())")
        if !fileManager.fileExists(atPath: target.path) { try fileManager.copyItem(at: sourceURL, to: target) }
        try database.recordCachedTrack(trackID: track.id, path: target.path, fileSize: track.fileSize)
        try evictIfNeeded()
        return target
    }

    func cachedPlayableURL(for track: Track) throws -> URL? {
        guard let path = try database.cachedPath(trackID: track.id),
              fileManager.fileExists(atPath: path) else { return nil }
        let url = URL(filePath: path)
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? track.fileSize
        try database.recordCachedTrack(trackID: track.id, path: path, fileSize: size)
        return url
    }

    func cacheForFavorite(_ track: Track) throws -> URL {
        try cache(track, pinned: true)
    }

    func cacheExplicitly(_ track: Track) throws -> URL {
        try cache(track, pinned: false)
    }

    private func cache(_ track: Track, pinned: Bool) throws -> URL {
        if let path = try database.cachedPath(trackID: track.id), fileManager.fileExists(atPath: path) {
            let url = URL(filePath: path)
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? track.fileSize
            try database.recordCachedTrack(trackID: track.id, path: path, fileSize: size, pinned: pinned)
            return url
        }

        guard let root = try database.scanRoot(id: track.rootID) else {
            throw MassiveMusicError.scanRootUnavailable
        }
        let scoped = try SecurityScopedRoot.resolve(bookmark: root.bookmark)
        return try scoped.withAccess { rootURL in
            guard fileManager.fileExists(atPath: rootURL.path) else {
                throw MassiveMusicError.scanRootUnavailable
            }
            let standardizedRoot = rootURL.standardizedFileURL
            let sourceURL = standardizedRoot.appending(path: track.relativePath).standardizedFileURL
            let prefix = standardizedRoot.path.hasSuffix("/") ? standardizedRoot.path : standardizedRoot.path + "/"
            guard sourceURL.path.hasPrefix(prefix), fileManager.fileExists(atPath: sourceURL.path) else {
                throw MassiveMusicError.trackUnavailable
            }
            let target = directory.appending(path: "\(track.id).\(track.format.lowercased())")
            if !fileManager.fileExists(atPath: target.path) {
                try fileManager.copyItem(at: sourceURL, to: target)
            }
            let size = (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? track.fileSize
            try database.recordCachedTrack(trackID: track.id, path: target.path, fileSize: size, pinned: pinned)
            try evictIfNeeded()
            return target
        }
    }

    func remove(trackID: Int64) throws {
        if let path = try database.cachedPath(trackID: trackID) {
            try? fileManager.removeItem(at: URL(filePath: path))
        }
        try database.removeCachedTrack(trackID: trackID)
    }

    func enforceLimit() throws {
        try evictIfNeeded()
    }

    func unpin(trackID: Int64) throws {
        try database.setCachedTrackPinned(trackID: trackID, pinned: false)
        try evictIfNeeded()
    }

    private func evictIfNeeded() throws {
        let limit = max(0, Int(try database.setting(forKey: "cache.trackLimit") ?? "24") ?? 24)
        for (trackID, path) in try database.cachedTracksBeyondLimit(limit) {
            try? fileManager.removeItem(at: URL(filePath: path))
            try database.removeCachedTrack(trackID: trackID)
        }
    }
}

enum MusicMetadataLookupError: LocalizedError {
    case missingTitle
    case invalidResponse
    case serviceUnavailable(Int)

    var errorDescription: String? {
        switch self {
        case .missingTitle: "曲名が空のため検索できません。"
        case .invalidResponse: "MusicBrainzから有効な応答を受信できませんでした。"
        case let .serviceUnavailable(status): "MusicBrainzへの接続に失敗しました（HTTP \(status)）。"
        }
    }
}

actor MusicBrainzMetadataService {
    private let session: URLSession
    private var lastRequestAt: ContinuousClock.Instant?
    private let clock = ContinuousClock()

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.httpAdditionalHeaders = [
            "Accept": "application/json",
            "User-Agent": "MassiveMusic/0.10 (local macOS music library)"
        ]
        session = URLSession(configuration: configuration)
    }

    func candidates(for track: Track) async throws -> [MusicMetadataCandidate] {
        let title = track.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw MusicMetadataLookupError.missingTitle }
        var terms = ["recording:\"\(quotedPhrase(title))\""]
        let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        if !artist.isEmpty { terms.append("artist:\"\(quotedPhrase(artist))\"") }
        let album = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
        if !album.isEmpty {
            let albumMatches = try await request(
                terms: terms + ["release:\"\(quotedPhrase(album))\""], matching: track
            )
            if !albumMatches.isEmpty { return albumMatches }
        }
        return try await request(terms: terms, matching: track)
    }

    private func request(terms: [String], matching track: Track) async throws -> [MusicMetadataCandidate] {
        if let lastRequestAt {
            let elapsed = lastRequestAt.duration(to: clock.now)
            let minimumInterval = Duration.milliseconds(1_100)
            if elapsed < minimumInterval { try await clock.sleep(for: minimumInterval - elapsed) }
        }
        try Task.checkCancellation()
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/recording/")!
        components.queryItems = [
            URLQueryItem(name: "query", value: terms.joined(separator: " AND ")),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "15")
        ]
        guard let url = components.url else { throw MusicMetadataLookupError.invalidResponse }
        lastRequestAt = clock.now
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw MusicMetadataLookupError.invalidResponse }
        guard http.statusCode == 200 else { throw MusicMetadataLookupError.serviceUnavailable(http.statusCode) }
        return try MusicBrainzMetadataMatcher.candidates(from: data, matching: track)
    }

    private func quotedPhrase(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

actor WebEnrichmentService {
    private struct LRCResponse: Decodable { let plainLyrics: String?; let syncedLyrics: String? }
    private let database: LibraryDatabase
    private let session: URLSession
    private let artworkDirectory: URL

    init(database: LibraryDatabase) {
        self.database = database
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpAdditionalHeaders = ["User-Agent": "MassiveMusic/0.2 (local macOS music library)"]
        session = URLSession(configuration: configuration)
        let base = (try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        artworkDirectory = base.appending(path: "MassiveMusic/WebArtwork", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
    }

    func info(for track: Track, languageCode: String) async -> EnrichedTrackInfo {
        let lyrics: CachedLyrics?
        if let cached = try? database.cachedLyrics(trackID: track.id) {
            lyrics = cached
        } else {
            lyrics = await fetchLyrics(for: track)
        }
        let wiki = await wikipediaURL(for: track.artist.isEmpty ? track.album : track.artist, languageCode: languageCode)
        let artwork: URL?
        if let embeddedArtwork = await embeddedArtworkURL(for: track) {
            artwork = embeddedArtwork
        } else if let remoteArtwork = await coverArtURL(for: track) {
            artwork = await cacheImage(from: remoteArtwork, key: "album-\(track.album)-\(track.artist)")
        } else {
            artwork = nil
        }
        return EnrichedTrackInfo(lyrics: lyrics, artworkURL: artwork, wikipediaURL: wiki, detectedGenre: track.genre.isEmpty ? nil : track.genre)
    }

    private func embeddedArtworkURL(for track: Track) async -> URL? {
        if let cachedPath = try? database.cachedPath(trackID: track.id),
           FileManager.default.fileExists(atPath: cachedPath) {
            if let cachedArtwork = await ArtworkCache.shared.imageURL(
                trackID: track.id, audioURL: URL(filePath: cachedPath)
            ) {
                return cachedArtwork
            }
        }
        guard track.hasArtwork,
              let root = try? database.scanRoot(id: track.rootID),
              let scope = try? SecurityScopedRoot.resolve(bookmark: root.bookmark) else { return nil }
        return try? await scope.withAccess { rootURL in
            let standardizedRoot = rootURL.standardizedFileURL
            let sourceURL = standardizedRoot.appending(path: track.relativePath).standardizedFileURL
            let prefix = standardizedRoot.path.hasSuffix("/") ? standardizedRoot.path : standardizedRoot.path + "/"
            guard sourceURL.path.hasPrefix(prefix), FileManager.default.fileExists(atPath: sourceURL.path) else { return nil }
            return await ArtworkCache.shared.imageURL(trackID: track.id, audioURL: sourceURL)
        }
    }

    private func fetchLyrics(for track: Track) async -> CachedLyrics? {
        var components = URLComponents(string: "https://lrclib.net/api/get")!
        components.queryItems = [
            URLQueryItem(name: "track_name", value: track.title),
            URLQueryItem(name: "artist_name", value: track.artist),
            URLQueryItem(name: "album_name", value: track.album),
            URLQueryItem(name: "duration", value: String(Int(track.duration)))
        ]
        guard let url = components.url,
              let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let result = try? JSONDecoder().decode(LRCResponse.self, from: data),
              let plain = result.plainLyrics, !plain.isEmpty else { return nil }
        try? database.saveLyrics(trackID: track.id, provider: "LRCLIB", plain: plain, synced: result.syncedLyrics)
        return try? database.cachedLyrics(trackID: track.id)
    }

    private func wikipediaURL(for query: String, languageCode: String) async -> URL? {
        guard !query.isEmpty else { return nil }
        let language = languageCode == "en" ? "en" : "ja"
        var components = URLComponents(string: "https://\(language).wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"), URLQueryItem(name: "list", value: "search"),
            URLQueryItem(name: "srsearch", value: query), URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "utf8", value: "1"), URLQueryItem(name: "srlimit", value: "1")
        ]
        guard let url = components.url, let (data, _) = try? await session.data(from: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let queryObject = object["query"] as? [String: Any],
              let search = queryObject["search"] as? [[String: Any]],
              let title = search.first?["title"] as? String else { return nil }
        return URL(string: "https://\(language).wikipedia.org/wiki/\(title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title)")
    }

    private func coverArtURL(for track: Track) async -> URL? {
        guard !track.album.isEmpty else { return nil }
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/release/")!
        let query = "release:\"\(track.album)\" AND artist:\"\(track.artist)\""
        components.queryItems = [URLQueryItem(name: "query", value: query), URLQueryItem(name: "fmt", value: "json"), URLQueryItem(name: "limit", value: "1")]
        guard let url = components.url, let (data, _) = try? await session.data(from: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let releases = object["releases"] as? [[String: Any]],
              let id = releases.first?["id"] as? String else { return nil }
        return URL(string: "https://coverartarchive.org/release/\(id)/front-500")
    }

    private func cacheImage(from url: URL, key: String) async -> URL? {
        let safe = String(key.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" })
        let destination = artworkDirectory.appending(path: String(safe.prefix(160)) + ".jpg")
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count <= 15 * 1_024 * 1_024 else { return nil }
        do { try data.write(to: destination, options: .atomic); return destination }
        catch { return nil }
    }
}
