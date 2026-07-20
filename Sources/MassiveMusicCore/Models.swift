import Foundation

public enum LibrarySection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case tracks = "曲"
    case recentlyAdded = "最近追加した曲"
    case upNext = "次に再生"
    case albums = "アルバム"
    case artists = "アーティスト"
    case genres = "ジャンル"
    case playlists = "プレイリスト"
    case folders = "フォルダ"
    case favorites = "お気に入り"
    case cache = "キャッシュ"
    case activityLog = "ログ"
    case diagnostics = "メタデータ診断"

    public var id: String { rawValue }
}

public enum StorageTopology {
    /// A separate Mac-local cache is only useful while the primary library is
    /// mounted outside the startup volume. Keep this path based so a detached
    /// external drive retains the same topology while it is unavailable.
    public static func usesSeparateLocalCache(primaryPath: String?) -> Bool {
        guard let primaryPath, !primaryPath.isEmpty else { return false }
        let standardized = URL(fileURLWithPath: primaryPath).standardizedFileURL.path
        return standardized == "/Volumes" || standardized.hasPrefix("/Volumes/")
    }
}

public enum LibraryActivityKind: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case added
    case addedToCache
    case addedToMainStorage
    case fileModified
    case metadataChanged
    case unavailable
    case restored
    case removedFromLibrary
    case movedToTrash

    public var id: String { rawValue }
}

public struct LibraryActivityChange: Codable, Hashable, Sendable {
    public let field: String
    public let oldValue: String
    public let newValue: String

    public init(field: String, oldValue: String, newValue: String) {
        self.field = field
        self.oldValue = oldValue
        self.newValue = newValue
    }
}

public struct LibraryActivityEvent: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let kind: LibraryActivityKind
    public let trackID: Int64?
    public let filename: String
    public let title: String
    public let artist: String
    public let album: String
    public let relativePath: String
    public let absolutePath: String
    public let changes: [LibraryActivityChange]
    public let occurredAt: Date

    public init(
        id: Int64, kind: LibraryActivityKind, trackID: Int64?, filename: String,
        title: String, artist: String, album: String, relativePath: String,
        absolutePath: String, changes: [LibraryActivityChange], occurredAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.trackID = trackID
        self.filename = filename
        self.title = title
        self.artist = artist
        self.album = album
        self.relativePath = relativePath
        self.absolutePath = absolutePath
        self.changes = changes
        self.occurredAt = occurredAt
    }
}

public struct LibraryActivityPage: Sendable {
    public let events: [LibraryActivityEvent]
    public let offset: Int
    public let limit: Int
    public let totalCount: Int
}

public enum MetadataIssueKind: String, CaseIterable, Identifiable, Equatable, Sendable {
    case missingTitle
    case missingArtist
    case missingAlbum
    case urlInMP3Metadata
    case suspectedMojibake
    case duplicateTracks
    case suspectedVariations
    public var id: String { rawValue }
}

public enum MetadataField: String, CaseIterable, Identifiable, Sendable {
    case title
    case artist
    case album
    public var id: String { rawValue }
}

public struct ExactMetadataFilter: Hashable, Sendable {
    public let field: MetadataField
    public let value: String

    public init(field: MetadataField, value: String) {
        self.field = field
        self.value = value
    }
}

public enum MetadataVariationReason: String, Sendable {
    case normalization
    case likelyTypo
}

public struct MetadataIssueSummary: Identifiable, Hashable, Sendable {
    public let kind: MetadataIssueKind
    public let count: Int
    public var id: MetadataIssueKind { kind }

    public init(kind: MetadataIssueKind, count: Int) {
        self.kind = kind
        self.count = count
    }
}

public struct MetadataVariationCandidate: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let field: MetadataField
    public let valueA: String
    public let valueB: String
    public let trackCountA: Int
    public let trackCountB: Int
    public let reason: MetadataVariationReason
    public let editDistance: Int
}

public struct MetadataTerm: Hashable, Sendable {
    public let value: String
    public let normalized: String
    public let trackCount: Int

    public init(value: String, normalized: String, trackCount: Int) {
        self.value = value
        self.normalized = normalized
        self.trackCount = trackCount
    }
}

public struct StoredMetadataTerm: Hashable, Sendable {
    public let id: Int64
    public let prefix: String
    public let term: MetadataTerm
}

public struct MetadataVariationPage: Sendable {
    public let candidates: [MetadataVariationCandidate]
    public let offset: Int
    public let limit: Int
    public let totalCount: Int
}

public struct MetadataAnalysisProgress: Sendable {
    public let field: MetadataField?
    public let processedTerms: Int
    public let candidates: Int
    public let isComplete: Bool

    public static let idle = MetadataAnalysisProgress(field: nil, processedTerms: 0, candidates: 0, isComplete: false)
}

public struct FacetPage: Sendable {
    public let facets: [Facet]
    public let offset: Int
    public let limit: Int
    public let totalCount: Int
}

public enum TrackSort: String, CaseIterable, Identifiable, Equatable, Sendable {
    case title = "タイトル"
    case artist = "アーティスト"
    case album = "アルバム"
    case discNumber = "ディスク番号"
    case trackNumber = "トラック番号"
    case dateAdded = "追加日"
    case path = "ファイルパス"
    case duration = "時間"
    case format = "形式"

    public var id: String { rawValue }
}

public enum SortDirection: String, CaseIterable, Identifiable, Equatable, Sendable {
    case ascending
    case descending
    public var id: String { rawValue }
}

public enum AlbumSort: String, CaseIterable, Identifiable, Equatable, Sendable {
    case name = "アルバム"
    case artist = "アーティスト"
    case trackCount = "曲数"
    public var id: String { rawValue }
}

public enum ArtistSort: String, CaseIterable, Identifiable, Equatable, Sendable {
    case name = "アーティスト"
    case albumCount = "アルバム数"
    case trackCount = "曲数"
    public var id: String { rawValue }
}

public enum TrackPlaybackScope: Equatable, Sendable {
    case library(query: String)
    case recentlyAdded(query: String)
    case album(name: String, artist: String)
    case artist(name: String)
    case genre(name: String)
    case favorites
    case cache(query: String)
    case playlist(id: Int64)
    case metadataIssue(kind: MetadataIssueKind)
    case metadataValue(field: MetadataField, value: String)
}

public struct TrackPlaybackContext: Equatable, Sendable {
    public let scope: TrackPlaybackScope
    public let sort: TrackSort
    public let direction: SortDirection

    public init(scope: TrackPlaybackScope, sort: TrackSort, direction: SortDirection) {
        self.scope = scope
        self.sort = sort
        self.direction = direction
    }
}

public struct Track: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let rootID: Int64
    public let relativePath: String
    public let filename: String
    public let title: String
    public let artist: String
    public let album: String
    public let albumArtist: String
    public let genre: String
    public let isCompilation: Bool
    public let discNumber: Int?
    public let trackNumber: Int?
    public let duration: Double
    public let fileSize: Int64
    public let modifiedAt: Date
    public let format: String
    public let bitrate: Int?
    public let hasArtwork: Bool
    public let isAvailable: Bool
    public let addedAt: Date
    public let isFavorite: Bool

    public init(
        id: Int64 = 0,
        rootID: Int64,
        relativePath: String,
        filename: String,
        title: String,
        artist: String = "",
        album: String = "",
        albumArtist: String = "",
        genre: String = "",
        isCompilation: Bool = false,
        discNumber: Int? = nil,
        trackNumber: Int? = nil,
        duration: Double = 0,
        fileSize: Int64,
        modifiedAt: Date,
        format: String,
        bitrate: Int? = nil,
        hasArtwork: Bool = false,
        isAvailable: Bool = true,
        addedAt: Date = Date(),
        isFavorite: Bool = false
    ) {
        self.id = id
        self.rootID = rootID
        self.relativePath = relativePath
        self.filename = filename
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.genre = genre
        self.isCompilation = isCompilation
        self.discNumber = discNumber
        self.trackNumber = trackNumber
        self.duration = duration
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
        self.format = format
        self.bitrate = bitrate
        self.hasArtwork = hasArtwork
        self.isAvailable = isAvailable
        self.addedAt = addedAt
        self.isFavorite = isFavorite
    }
}

public struct TrackMetadataEdit: Hashable, Codable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var albumArtist: String
    public var genre: String
    public var isCompilation: Bool
    public var discNumber: Int?
    public var trackNumber: Int?
    public var artworkData: Data?

    public init(track: Track) {
        title = track.title
        artist = track.artist
        album = track.album
        albumArtist = track.albumArtist
        genre = track.genre
        isCompilation = track.isCompilation
        discNumber = track.discNumber
        trackNumber = track.trackNumber
        artworkData = nil
    }

    /// Removes only leading ASCII and Japanese full-width spaces from a title.
    /// Spaces inside or at the end of the title remain untouched.
    public func normalizingLeadingTitleSpaces() -> TrackMetadataEdit {
        var normalized = self
        normalized.title = String(title.drop(while: { $0 == " " || $0 == "　" }))
        return normalized
    }

    /// Normalizes only character-width variants. Broad compatibility
    /// normalization is intentionally avoided so Roman numerals, circled
    /// numbers, ligatures, and intentional spacing remain untouched.
    public func normalizingCharacterWidths() -> TrackMetadataEdit {
        var normalized = self
        normalized.title = MetadataTextNormalizer.normalizedWidths(title)
        normalized.artist = MetadataTextNormalizer.normalizedWidths(artist)
        normalized.album = MetadataTextNormalizer.normalizedWidths(album)
        normalized.albumArtist = MetadataTextNormalizer.normalizedWidths(albumArtist)
        normalized.genre = MetadataTextNormalizer.normalizedWidths(genre)
        return normalized
    }

    public func hasTextChanges(comparedWith track: Track) -> Bool {
        title != track.title || artist != track.artist || album != track.album
            || albumArtist != track.albumArtist || genre != track.genre
    }
}

public struct PendingMetadataEdit: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let trackID: Int64
    public let edit: TrackMetadataEdit
    public let updatedAt: Date

    public init(id: Int64, trackID: Int64, edit: TrackMetadataEdit, updatedAt: Date) {
        self.id = id
        self.trackID = trackID
        self.edit = edit
        self.updatedAt = updatedAt
    }
}

public extension Track {
    /// Returns an in-memory representation of metadata that was successfully written to the file.
    func applying(_ edit: TrackMetadataEdit) -> Track {
        Track(
            id: id,
            rootID: rootID,
            relativePath: relativePath,
            filename: filename,
            title: edit.title,
            artist: edit.artist,
            album: edit.album,
            albumArtist: edit.albumArtist,
            genre: edit.genre,
            isCompilation: edit.isCompilation,
            discNumber: edit.discNumber,
            trackNumber: edit.trackNumber,
            duration: duration,
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            format: format,
            bitrate: bitrate,
            hasArtwork: edit.artworkData != nil || hasArtwork,
            isAvailable: isAvailable,
            addedAt: addedAt,
            isFavorite: isFavorite
        )
    }
}

public enum MetadataTextNormalizer {
    public static func normalizedWidths(_ value: String) -> String {
        var result = ""
        var halfwidthKana = String.UnicodeScalarView()

        func appendKana() {
            guard !halfwidthKana.isEmpty else { return }
            result.append(String(halfwidthKana).precomposedStringWithCompatibilityMapping)
            halfwidthKana.removeAll(keepingCapacity: true)
        }

        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0xFF61...0xFF9F:
                halfwidthKana.append(scalar)
            case 0xFF01...0xFF5E:
                appendKana()
                if let ascii = UnicodeScalar(scalar.value - 0xFEE0) {
                    result.unicodeScalars.append(ascii)
                }
            default:
                appendKana()
                result.unicodeScalars.append(scalar)
            }
        }
        appendKana()
        return result
    }
}

public struct ReleaseTrack: Codable, Hashable, Sendable {
    public let discNumber: Int
    public let trackNumber: Int
    public let title: String
    public let artist: String
    
    public init(discNumber: Int, trackNumber: Int, title: String, artist: String) {
        self.discNumber = discNumber
        self.trackNumber = trackNumber
        self.title = title
        self.artist = artist
    }
}

public struct MusicMetadataCandidate: Identifiable, Hashable, Sendable {
    public let id: String
    public let releaseID: String
    public let recordingTitle: String
    public let artist: String
    public let album: String
    public let albumArtist: String
    public let discNumber: Int
    public let trackNumber: Int
    public let mediumTrackCount: Int?
    public let releaseDate: String?
    public let releaseStatus: String?
    public let matchScore: Int

    public init(
        id: String,
        releaseID: String,
        recordingTitle: String,
        artist: String,
        album: String,
        albumArtist: String,
        discNumber: Int,
        trackNumber: Int,
        mediumTrackCount: Int?,
        releaseDate: String?,
        releaseStatus: String?,
        matchScore: Int
    ) {
        self.id = id
        self.releaseID = releaseID
        self.recordingTitle = recordingTitle
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.discNumber = discNumber
        self.trackNumber = trackNumber
        self.mediumTrackCount = mediumTrackCount
        self.releaseDate = releaseDate
        self.releaseStatus = releaseStatus
        self.matchScore = matchScore
    }
}

public enum MusicBrainzMetadataMatcher {
    public static func candidates(from data: Data, matching track: Track) throws -> [MusicMetadataCandidate] {
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        var candidates: [MusicMetadataCandidate] = []

        for recording in response.recordings {
            let recordingArtist = joinedCredit(recording.artistCredit)
            for release in recording.releases ?? [] {
                let albumArtist = joinedCredit(release.artistCredit)
                for medium in release.media ?? [] {
                    for releaseTrack in medium.tracks ?? [] {
                        let trackNumber = integerTrackNumber(releaseTrack.number)
                            ?? medium.trackOffset.map { $0 + 1 }
                        guard let trackNumber, trackNumber > 0, medium.position > 0 else { continue }
                        let duration = releaseTrack.length ?? recording.length
                        let score = matchScore(
                            track: track,
                            recordingTitle: recording.title,
                            recordingArtist: recordingArtist,
                            album: release.title,
                            durationMilliseconds: duration,
                            apiScore: recording.score,
                            status: release.status,
                            format: medium.format
                        )
                        candidates.append(MusicMetadataCandidate(
                            id: "\(release.id)-\(medium.position)-\(trackNumber)",
                            releaseID: release.id,
                            recordingTitle: recording.title,
                            artist: recordingArtist,
                            album: release.title,
                            albumArtist: albumArtist,
                            discNumber: medium.position,
                            trackNumber: trackNumber,
                            mediumTrackCount: medium.trackCount,
                            releaseDate: release.date,
                            releaseStatus: release.status,
                            matchScore: score
                        ))
                    }
                }
            }
        }

        var seen = Set<String>()
        return candidates
            .sorted {
                if $0.matchScore != $1.matchScore { return $0.matchScore > $1.matchScore }
                let leftDate = $0.releaseDate ?? "9999"
                let rightDate = $1.releaseDate ?? "9999"
                if leftDate != rightDate { return leftDate < rightDate }
                return $0.album.localizedStandardCompare($1.album) == .orderedAscending
            }
            .filter { seen.insert($0.id).inserted }
    }

    private static func matchScore(
        track: Track,
        recordingTitle: String,
        recordingArtist: String,
        album: String,
        durationMilliseconds: Int?,
        apiScore: Int?,
        status: String?,
        format: String?
    ) -> Int {
        var score = apiScore ?? 0
        if normalized(recordingTitle) == normalized(track.title) { score += 30 }
        if !track.artist.isEmpty, normalized(recordingArtist) == normalized(track.artist) { score += 30 }
        if !track.album.isEmpty, normalized(album) == normalized(track.album) { score += 40 }
        if let durationMilliseconds, track.duration > 0 {
            let difference = abs(Double(durationMilliseconds) / 1_000 - track.duration)
            if difference <= 2 { score += 20 }
            else if difference <= 5 { score += 12 }
            else if difference <= 15 { score += 4 }
        }
        if status?.localizedCaseInsensitiveCompare("Official") == .orderedSame { score += 10 }
        let normalizedFormat = format?.lowercased() ?? ""
        if normalizedFormat.contains("dvd") || normalizedFormat.contains("blu-ray") { score -= 15 }
        return score
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func integerTrackNumber(_ value: String?) -> Int? {
        guard let value else { return nil }
        if let exact = Int(value) { return exact }
        let digits = value.drop { !$0.isNumber }.prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    private static func joinedCredit(_ credits: [ArtistCredit]?) -> String {
        credits?.map { credit in
            (credit.name ?? credit.artist?.name ?? "") + (credit.joinphrase ?? "")
        }.joined() ?? ""
    }

    private struct SearchResponse: Decodable {
        let recordings: [Recording]
    }

    private struct Recording: Decodable {
        let id: String
        let title: String
        let score: Int?
        let length: Int?
        let artistCredit: [ArtistCredit]?
        let releases: [Release]?

        enum CodingKeys: String, CodingKey {
            case id, title, score, length, releases
            case artistCredit = "artist-credit"
        }
    }

    private struct Release: Decodable {
        let id: String
        let title: String
        let status: String?
        let date: String?
        let artistCredit: [ArtistCredit]?
        let media: [Medium]?

        enum CodingKeys: String, CodingKey {
            case id, title, status, date, media
            case artistCredit = "artist-credit"
        }
    }

    private struct Medium: Decodable {
        let position: Int
        let format: String?
        let tracks: [ReleaseTrack]?
        let trackOffset: Int?
        let trackCount: Int?

        enum CodingKeys: String, CodingKey {
            case position, format
            case tracks = "track"
            case trackOffset = "track-offset"
            case trackCount = "track-count"
        }
    }

    private struct ReleaseTrack: Decodable {
        let number: String?
        let length: Int?
    }

    private struct ArtistCredit: Decodable {
        let name: String?
        let joinphrase: String?
        let artist: CreditedArtist?
    }

    private struct CreditedArtist: Decodable { let name: String }
}

public struct BatchMetadataChanges: Equatable, Sendable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var albumArtist: String?
    public var genre: String?
    public var isCompilation: Bool?
    public var discNumber: Int?
    public var changesDiscNumber: Bool
    public var trackNumber: Int?
    public var changesTrackNumber: Bool
    public var incrementsTrackNumber: Bool
    public var artworkData: Data?

    public init(
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        albumArtist: String? = nil,
        genre: String? = nil,
        isCompilation: Bool? = nil,
        discNumber: Int? = nil,
        changesDiscNumber: Bool = false,
        trackNumber: Int? = nil,
        changesTrackNumber: Bool = false,
        incrementsTrackNumber: Bool = false,
        artworkData: Data? = nil
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.genre = genre
        self.isCompilation = isCompilation
        self.discNumber = discNumber
        self.changesDiscNumber = changesDiscNumber
        self.trackNumber = trackNumber
        self.changesTrackNumber = changesTrackNumber
        self.incrementsTrackNumber = incrementsTrackNumber
        self.artworkData = artworkData
    }

    public var isEmpty: Bool {
        title == nil && artist == nil && album == nil && albumArtist == nil && genre == nil && isCompilation == nil &&
            !changesDiscNumber && !changesTrackNumber && artworkData == nil
    }

    public func applying(to track: Track, offset: Int = 0) -> TrackMetadataEdit {
        var edit = TrackMetadataEdit(track: track)
        if let title { edit.title = title }
        if let artist { edit.artist = artist }
        if let album { edit.album = album }
        if let albumArtist { edit.albumArtist = albumArtist }
        if let genre { edit.genre = genre }
        if let isCompilation { edit.isCompilation = isCompilation }
        if changesDiscNumber { edit.discNumber = discNumber }
        if changesTrackNumber {
            edit.trackNumber = trackNumber.map { $0 + (incrementsTrackNumber ? offset : 0) }
        }
        if let artworkData { edit.artworkData = artworkData }
        return edit
    }
}

public enum ImportState: String, Sendable, Codable {
    case staged
    case moved
    case keptLocal
    case failed
}

public struct PendingImport: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let localPath: String
    public let filename: String
    public let state: ImportState
    public let createdAt: Date
    public let errorMessage: String?
}

public struct StorageDestination: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let name: String
    public let path: String
    public let bookmark: Data
    public let isPrimary: Bool
    public let isAvailable: Bool
}

public enum LibraryDifferenceKind: String, Sendable, Codable {
    case registeredButMissing
    case onStorageButUnregistered
}

public struct LibraryDifference: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let rootID: Int64
    public let relativePath: String
    public let kind: LibraryDifferenceKind
}

public struct CachedLyrics: Sendable, Hashable {
    public let trackID: Int64
    public let provider: String
    public let plainLyrics: String
    public let syncedLyrics: String?
    public let updatedAt: Date
}

public struct TrackPage: Sendable {
    public let tracks: [Track]
    public let offset: Int
    public let limit: Int
    public let totalCount: Int

    public var hasPrevious: Bool { offset > 0 }
    public var hasNext: Bool { offset + tracks.count < totalCount }
}

public struct Facet: Identifiable, Hashable, Sendable {
    public let name: String
    public let count: Int
    public var id: String { name }
}

public struct AlbumSummary: Identifiable, Hashable, Sendable {
    public let name: String
    public let artist: String
    public let trackCount: Int
    public var id: String { "\(name)\u{1F}\(artist)" }

    public init(name: String, artist: String, trackCount: Int) {
        self.name = name
        self.artist = artist
        self.trackCount = trackCount
    }
}

public struct AlbumSummaryPage: Sendable {
    public let albums: [AlbumSummary]
    public let offset: Int
    public let limit: Int
    public let totalCount: Int
}

public struct ArtistSummary: Identifiable, Hashable, Sendable {
    public let name: String
    public let albumCount: Int
    public let trackCount: Int
    public var id: String { name }

    public init(name: String, albumCount: Int, trackCount: Int) {
        self.name = name
        self.albumCount = albumCount
        self.trackCount = trackCount
    }
}

public struct ArtistSummaryPage: Sendable {
    public let artists: [ArtistSummary]
    public let offset: Int
    public let limit: Int
    public let totalCount: Int
}

public struct LibraryStorageSummary: Equatable, Sendable {
    public let totalBytes: Int64
    public let absoluteRootPaths: [String]

    public init(totalBytes: Int64, absoluteRootPaths: [String]) {
        self.totalBytes = totalBytes
        self.absoluteRootPaths = absoluteRootPaths
    }

    public static let empty = LibraryStorageSummary(totalBytes: 0, absoluteRootPaths: [])
}

public struct Playlist: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let name: String
    public let itemCount: Int
}

public struct ScanRoot: Identifiable, Hashable, Sendable {
    public let id: Int64
    public let displayName: String
    public let bookmark: Data
    public let volumeUUID: String?
    public let lastKnownPath: String
    public let isAvailable: Bool
}

public enum ScanState: String, Sendable {
    case running
    case paused
    case cancelled
    case failed
    case completed
}

public struct ScanProgress: Sendable {
    public let sessionID: Int64
    public let state: ScanState
    public let discovered: Int
    public let processed: Int
    public let insertedOrUpdated: Int
    public let skipped: Int
    public let errors: Int
    public let tracksPerSecond: Double
    public let currentPath: String

    public static let idle = ScanProgress(
        sessionID: 0,
        state: .completed,
        discovered: 0,
        processed: 0,
        insertedOrUpdated: 0,
        skipped: 0,
        errors: 0,
        tracksPerSecond: 0,
        currentPath: ""
    )
}

public struct TrackImport: Sendable {
    public let identityKey: String
    public let fileResourceID: String?
    public let track: Track

    public init(identityKey: String, fileResourceID: String?, track: Track) {
        self.identityKey = identityKey
        self.fileResourceID = fileResourceID
        self.track = track
    }
}

public struct SyntheticBenchmarkResult: Codable, Sendable {
    public let requestedCount: Int
    public let insertedCount: Int
    public let insertSeconds: Double
    public let searchMilliseconds: Double
    public let pageMilliseconds: Double
    public let deepOffsetMilliseconds: Double
    public let playlist100kSeconds: Double
    public let playlistPageMilliseconds: Double
    public let databaseBytes: Int64
    public let generatedAt: Date
}

public enum MassiveMusicError: LocalizedError, Sendable {
    case invalidPageSize
    case scanRootUnavailable
    case bookmarkResolutionFailed
    case trackUnavailable
    case unsupportedAudioFormat(String)
    case metadataWriteFailed(String)
    case invalidPlaylistName

    public var errorDescription: String? {
        switch self {
        case .invalidPageSize: "ページサイズが不正です。"
        case .scanRootUnavailable: "ドライブが接続されていません。"
        case .bookmarkResolutionFailed: "音楽フォルダへのアクセス権を復元できません。"
        case .trackUnavailable: "曲ファイルを利用できません。"
        case let .unsupportedAudioFormat(ext): "未対応の音声形式です: \(ext)"
        case let .metadataWriteFailed(reason): "曲情報を書き込めませんでした: \(reason)"
        case .invalidPlaylistName: "プレイリスト名を入力してください。"
        }
    }

    public var isRepairableID3Damage: Bool {
        guard case let .metadataWriteFailed(reason) = self else { return false }
        return reason.contains("ID3フレーム") || reason.contains("ID3タグ") || reason.contains("ID3v2")
    }
}
