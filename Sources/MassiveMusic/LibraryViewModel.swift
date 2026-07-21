import AppKit
import Combine
import UniformTypeIdentifiers
import Foundation
import MassiveMusicCore
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case japanese = "ja"
    case english = "en"
    var id: String { rawValue }
    var displayName: String { self == .japanese ? "日本語" : "English" }
    var locale: Locale { Locale(identifier: rawValue) }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

enum GenreDetailMode: String, CaseIterable, Identifiable {
    case albums
    case artists
    case tracks
    var id: String { rawValue }
}

private enum LibraryIndexTarget: Sendable {
    case tracks
    case albums
    case artists
}

enum BatchMetadataState: Equatable, Sendable {
    case idle
    case running
    case completed
    case cancelled
}

struct BatchMetadataProgress: Sendable {
    var state: BatchMetadataState = .idle
    var total = 0
    var processed = 0
    var succeeded = 0
    var failed = 0
    var currentFilename = ""

    static let idle = BatchMetadataProgress()
}

struct ImportProgress: Sendable {
    var state: State = .idle
    var currentFileIndex = 0
    var totalFiles = 0
    var fileProgress = 0.0
    var currentFileName = ""
    
    enum State: Equatable {
        case idle
        case converting
        case moving
        case completed
        case failed(String)
    }
    
    static let idle = ImportProgress()
}

struct MetadataRepairRequest: Identifiable, Sendable {
    let id = UUID()
    let track: Track
    let edit: TrackMetadataEdit
}

private struct BrowseReturnState {
    let section: LibrarySection
    let sort: TrackSort
    let sortDirection: SortDirection
    let searchText: String
    let selectedPlaylistID: Int64?
    let selectedAlbum: AlbumSummary?
    let selectedArtist: ArtistSummary?
    let selectedGenre: String?
    let genreDetailMode: GenreDetailMode
    let offset: Int
    let trackPageCursors: [Track?]
    let usesDirectOffsetPaging: Bool
    let selectedTrackIDs: Set<Int64>
    let selectedIndexToken: String?
}

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var section: LibrarySection = .tracks
    @Published private(set) var librarySectionOrder: [LibrarySection] = []
    @Published var sort: TrackSort = .title
    @Published var sortDirection: SortDirection = .ascending
    @Published var albumSort: AlbumSort = .name
    @Published var albumSortDirection: SortDirection = .ascending
    @Published var artistSort: ArtistSort = .name
    @Published var artistSortDirection: SortDirection = .ascending
    @Published var searchText = ""
    @Published private(set) var isSearchPending = false
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var activityEvents: [LibraryActivityEvent] = []
    @Published private(set) var storageSyncEvents: [LibraryActivityEvent] = []
    @Published var activityKindFilter: LibraryActivityKind? = nil
    @Published var activityCategoryFilter: ActivityLogCategoryFilter = .all
    @Published private(set) var facets: [Facet] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published var selectedTrackIDs: Set<Int64> = []
    @Published var selectedIndexToken: String?
    @Published var selectedPlaylistID: Int64?
    @Published private(set) var offset = 0
    @Published private(set) var totalCount = 0
    @Published private(set) var favoriteTrackCount = 0
    @Published private(set) var recentlyAddedTrackCount = 0
    @Published private(set) var isLoading = false

    var isStorageExternal: Bool {
        StorageTopology.usesSeparateLocalCache(
            primaryPath: storageDestinations.first(where: \.isPrimary)?.path
        )
    }

    var visibleLibrarySections: [LibrarySection] {
        let reorderable = LibrarySection.allCases.filter(Self.isReorderableLibrarySection)
        let ordered = librarySectionOrder + reorderable.filter { !librarySectionOrder.contains($0) }
        return ordered.filter { section in
            switch section {
            case .playlists, .diagnostics, .activityLog:
                false
            case .cache:
                isStorageExternal
            default:
                true
            }
        }
    }
    @Published private(set) var scanProgress = ScanProgress.idle
    @Published private(set) var driveMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var metadataRepairRequest: MetadataRepairRequest?
    @Published private(set) var pendingImports: [PendingImport] = []
    @Published private(set) var storageDestinations: [StorageDestination] = []
    @Published private(set) var primaryStorageIsConnected = false
    @Published var cacheEnabled = true
    @Published var cacheTrackLimit = 24
    @Published var autoFillMusicBrainzTrackNumbers = true
    @Published var isBulkAutoFilling = false
    @Published var bulkAutoFillProgress = ""
    @Published var normalizeMetadataCharacterWidths = false
    @Published var autoMigrateID3v22ToV23 = true
    @Published var isID3Migrating = false
    @Published var id3MigrationProgress = ""
    @Published private(set) var cachedTrackIDs: Set<Int64> = []
    @Published private(set) var unavailableRootIDs: Set<Int64> = []
    @Published private(set) var missingVisibleTrackIDs: Set<Int64> = []
    @Published private(set) var cachingTrackIDs: Set<Int64> = []
    @Published private(set) var enrichedInfo: EnrichedTrackInfo?
    @Published private(set) var similarTracks: [Track] = []
    @Published private(set) var isEnriching = false
    @Published private(set) var unavailableTrackCount = 0
    @Published private(set) var albumSummaries: [AlbumSummary] = []
    @Published private(set) var artistSummaries: [ArtistSummary] = []
    @Published private(set) var albumArtworkURLs: [String: URL] = [:]
    @Published private(set) var artistImageURLs: [String: URL] = [:]
    @Published private(set) var headerStorageSummary: LibraryStorageSummary?
    @Published var selectedAlbum: AlbumSummary?
    @Published var selectedArtist: ArtistSummary?
    @Published var selectedGenre: String?
    @Published var genreDetailMode: GenreDetailMode = .albums
    @Published var language: AppLanguage
    @Published var appearance: AppearanceMode
    @Published var diagnosticKind: MetadataIssueKind = .missingArtist
    @Published private(set) var diagnosticSummaries: [MetadataIssueSummary] = []
    @Published private(set) var variationCandidates: [MetadataVariationCandidate] = []
    @Published private(set) var exactMetadataFilter: ExactMetadataFilter?
    @Published private(set) var metadataAnalysisProgress = MetadataAnalysisProgress.idle
    @Published private(set) var isAnalyzingMetadata = false
    @Published private(set) var hasOpenAIAPIKey = false
    @Published private(set) var hasGeminiAPIKey = false
    @Published private(set) var openAIStatus: AIProviderStatus = .notConfigured
    @Published private(set) var geminiStatus: AIProviderStatus = .notConfigured
    @Published var openAIModel: String
    @Published var geminiModel: String
    @Published private(set) var aiFallbackMessage: String?
    @Published private(set) var genreSuggestion: GenreSuggestion?
    @Published private(set) var isClassifyingGenre = false
    @Published private(set) var batchMetadataProgress = BatchMetadataProgress.idle
    @Published var importProgress = ImportProgress.idle

    let pageSize = 200
    let activityPageSize = 100
    private let database: LibraryDatabase
    private let scanner: LibraryScanner
    private let storage: StorageCoordinator
    private let trackFiles: TrackFileCoordinator
    private let offlineCache: OfflineCacheManager
    private let enrichment: WebEnrichmentService
    private let musicMetadata = MusicBrainzMetadataService()
    private let metadataAnalyzer: MetadataDiagnosticsAnalyzer
    private let openAIKeychain = ProviderAPIKeychain.openAI
    private let geminiKeychain = ProviderAPIKeychain.gemini
    private let genreClassifier = OpenAIGenreClassifier()
    private var automaticallyClassifiedTrackIDs: Set<Int64> = []
    private let geminiGenreClassifier = GeminiGenreClassifier()
    private let localGenreClassifier = LocalGenreClassifier()
    private var searchTask: Task<Void, Never>?
    private var pageLoadTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var driveMonitor: Task<Void, Never>?
    private var trackPageCursors: [Track?] = [nil]
    private var metadataAnalysisTask: Task<Void, Never>?
    private var metadataSummaryTask: Task<Void, Never>?
    private var batchMetadataTask: Task<Void, Never>?
    private var leadingTitleSpaceCleanupTask: Task<Void, Never>?
    private var widthNormalizationTask: Task<Void, Never>?
    private var bulkAutoFillTask: Task<Void, Never>?
    private var id3MigrationTask: Task<Void, Never>?
    private var enrichmentTask: Task<Void, Never>?
    private var loadingAlbumArtworkIDs: Set<String> = []
    private var loadingArtistImageNames: Set<String> = []
    private var enrichedTrackID: Int64?
    private var usesDirectOffsetPaging = false
    private var headerStorageScope: String?
    private var isSyncingOffline = false
    private var isSyncingPendingMetadata = false
    private var browseReturnStack: [BrowseReturnState] = []

    init(database: LibraryDatabase, scanner: LibraryScanner) {
        self.database = database
        self.scanner = scanner
        storage = StorageCoordinator(database: database)
        trackFiles = TrackFileCoordinator(database: database)
        offlineCache = OfflineCacheManager(database: database)
        enrichment = WebEnrichmentService(database: database)
        metadataAnalyzer = MetadataDiagnosticsAnalyzer(database: database)
        language = AppLanguage(rawValue: (try? database.setting(forKey: "app.language")) ?? "ja") ?? .japanese
        appearance = AppearanceMode(rawValue: (try? database.setting(forKey: "app.appearance")) ?? "system") ?? .system
        openAIModel = (try? database.setting(forKey: "openai.model")) ?? "gpt-5.6-luna"
        geminiModel = (try? database.setting(forKey: "gemini.model")) ?? "gemini-3.5-flash"
        cacheEnabled = (try? database.setting(forKey: "cache.enabled")) != "false"
        cacheTrackLimit = Int((try? database.setting(forKey: "cache.trackLimit")) ?? "24") ?? 24
        autoFillMusicBrainzTrackNumbers = (try? database.setting(forKey: "musicbrainz.autoFillTrackNumbers")) != "false"
        normalizeMetadataCharacterWidths = (try? database.setting(forKey: "metadata.normalizeCharacterWidths")) == "true"
        autoMigrateID3v22ToV23 = (try? database.setting(forKey: "metadata.autoMigrateID3v22ToV23")) != "false"
        librarySectionOrder = Self.decodeLibrarySectionOrder(
            (try? database.setting(forKey: "sidebar.libraryOrder"))
        )
        // A playlist menu can be opened immediately after launch. This query is
        // tiny and bounded by the number of playlists, so populate it before the
        // first frame instead of briefly presenting an empty submenu.
        playlists = (try? database.playlists()) ?? []
        loadCurrentPage(reset: true)
        refreshPlaylists()
        refreshSidebarCounts()
        refreshStorage()
        refreshDifferenceSummary()
        restoreAIProviderConfigurationWithoutReadingKeys()
        ensureDefaultStorageDestination()
        driveMonitor = Task { [weak self] in await self?.monitorDrives() }
        startLeadingTitleSpaceCleanup()
        startBulkAutoFillIfNeeded()
        startID3Migration()
    }

    var canGoPrevious: Bool { offset > 0 }
    var canGoNext: Bool { offset + visibleItemCount < totalCount }
    private var activePageSize: Int { section == .activityLog ? activityPageSize : pageSize }
    var currentPageNumber: Int { totalCount == 0 ? 0 : (offset / activePageSize) + 1 }
    var pageCount: Int { totalCount == 0 ? 0 : Int(ceil(Double(totalCount) / Double(activePageSize))) }
    var isInDetail: Bool { selectedAlbum != nil || selectedArtist != nil || selectedGenre != nil }
    var supportsAlphabetIndex: Bool { alphabetIndexTarget != nil }
    var trackPlaybackContext: TrackPlaybackContext? {
        let scope: TrackPlaybackScope
        if section == .diagnostics {
            guard diagnosticKind != .suspectedVariations else { return nil }
            scope = .metadataIssue(kind: diagnosticKind)
        } else if let exactMetadataFilter {
            scope = .metadataValue(field: exactMetadataFilter.field, value: exactMetadataFilter.value)
        } else if let selectedAlbum {
            scope = .album(name: selectedAlbum.name, artist: selectedAlbum.artist)
        } else if let selectedArtist, selectedArtist.name.isEmpty {
            scope = .artist(name: "")
        } else if let selectedGenre, genreDetailMode == .tracks {
            scope = .genre(name: selectedGenre)
        } else if section == .favorites {
            scope = .favorites
        } else if section == .cache {
            scope = .cache(query: searchText)
        } else if section == .recentlyAdded {
            scope = .recentlyAdded(query: searchText)
        } else if section == .playlists, let selectedPlaylistID {
            scope = .playlist(id: selectedPlaylistID)
        } else if section == .tracks {
            scope = .library(query: searchText)
        } else {
            return nil
        }
        return TrackPlaybackContext(scope: scope, sort: sort, direction: sortDirection)
    }

    func text(_ japanese: String, _ english: String) -> String { language == .japanese ? japanese : english }

    func sectionTitle(_ section: LibrarySection) -> String {
        switch section {
        case .tracks: text("曲", "Songs")
        case .recentlyAdded: text("最近追加した曲", "Recently Added")
        case .upNext: text("次に再生", "Up Next")
        case .albums: text("アルバム", "Albums")
        case .artists: text("アーティスト", "Artists")
        case .genres: text("ジャンル", "Genres")
        case .playlists: text("プレイリスト", "Playlists")
        case .folders: text("フォルダ", "Folders")
        case .favorites: text("お気に入り", "Favorites")
        case .cache: text("キャッシュ", "Cache")
        case .activityLog: text("ログ", "Activity Log")
        case .diagnostics: text("メタデータ診断", "Metadata Diagnostics")
        }
    }

    func displayArtist(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? text("不明なアーティスト", "Unknown Artist") : value
    }

    func sortTitle(_ sort: TrackSort) -> String {
        switch sort {
        case .title: text("タイトル", "Title")
        case .artist: text("アーティスト", "Artist")
        case .album: text("アルバム", "Album")
        case .discNumber: text("ディスク番号", "Disc Number")
        case .trackNumber: text("トラック番号", "Track Number")
        case .dateAdded: text("追加日", "Date Added")
        case .path: text("ファイルパス", "File Path")
        case .duration: text("時間", "Duration")
        case .format: text("形式", "Format")
        }
    }

    func searchChanged() {
        searchTask?.cancel()
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isSearchPending = false
            selectedIndexToken = nil
            loadCurrentPage(reset: true)
            return
        }
        isSearchPending = true
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            self?.isSearchPending = false
            if self?.section != .cache && self?.section != .activityLog && self?.section != .recentlyAdded {
                self?.section = .tracks
            }
            self?.selectedPlaylistID = nil
            self?.selectedAlbum = nil
            self?.selectedArtist = nil
            self?.selectedGenre = nil
            self?.exactMetadataFilter = nil
            self?.selectedIndexToken = nil
            self?.browseReturnStack.removeAll()
            self?.loadCurrentPage(reset: true)
        }
    }

    var isSearchInProgress: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (isSearchPending || isLoading)
    }

    func clearSearch() {
        guard !searchText.isEmpty else { return }
        searchText = ""
    }

    func dismissError() { errorMessage = nil }

    func cancelMetadataRepair() { metadataRepairRequest = nil }

    func changeSection(_ newSection: LibrarySection, exactFilter: ExactMetadataFilter? = nil) {
        usesDirectOffsetPaging = false
        browseReturnStack.removeAll()
        selectedIndexToken = nil
        section = newSection
        selectedAlbum = nil
        selectedArtist = nil
        selectedGenre = nil
        exactMetadataFilter = exactFilter
        if newSection != .playlists { selectedPlaylistID = nil }
        if newSection == .diagnostics { refreshMetadataDiagnostics() }
        if newSection == .tracks, exactFilter == nil {
            sort = .title
            sortDirection = .ascending
        }
        if newSection == .recentlyAdded {
            sort = .dateAdded
            sortDirection = .descending
        }
        if newSection == .upNext {
            tracks = []
            facets = []
            albumSummaries = []
            artistSummaries = []
            totalCount = 0
            isLoading = false
            return
        }
        loadCurrentPage(reset: true)
    }

    func selectDiagnostic(_ kind: MetadataIssueKind) {
        diagnosticKind = kind
        refreshMetadataDiagnostics()
        loadCurrentPage(reset: true)
    }

    func moveLibrarySection(_ source: LibrarySection, before destination: LibrarySection) {
        guard source != destination,
              Self.isReorderableLibrarySection(source),
              Self.isReorderableLibrarySection(destination) else { return }
        let reorderable = LibrarySection.allCases.filter(Self.isReorderableLibrarySection)
        var order = librarySectionOrder + reorderable.filter { !librarySectionOrder.contains($0) }
        guard let sourceIndex = order.firstIndex(of: source) else { return }
        order.remove(at: sourceIndex)
        guard let destinationIndex = order.firstIndex(of: destination) else { return }
        order.insert(source, at: destinationIndex)
        saveLibrarySectionOrder(order)
    }

    func moveLibrarySection(_ source: LibrarySection, by offset: Int) {
        guard offset != 0 else { return }
        let visible = visibleLibrarySections
        guard let sourceIndex = visible.firstIndex(of: source) else { return }
        let destinationIndex = sourceIndex + offset
        guard visible.indices.contains(destinationIndex) else { return }

        let destination = visible[destinationIndex]
        let reorderable = LibrarySection.allCases.filter(Self.isReorderableLibrarySection)
        var order = librarySectionOrder + reorderable.filter { !librarySectionOrder.contains($0) }
        guard let firstIndex = order.firstIndex(of: source),
              let secondIndex = order.firstIndex(of: destination) else { return }
        order.swapAt(firstIndex, secondIndex)
        saveLibrarySectionOrder(order)
    }

    private func saveLibrarySectionOrder(_ order: [LibrarySection]) {
        librarySectionOrder = order
        do {
            try database.setSetting(order.map(\.rawValue).joined(separator: "\n"), forKey: "sidebar.libraryOrder")
        } catch { errorMessage = error.localizedDescription }
    }

    private static func isReorderableLibrarySection(_ section: LibrarySection) -> Bool {
        switch section {
        case .playlists, .diagnostics, .activityLog: false
        default: true
        }
    }

    private static func decodeLibrarySectionOrder(_ stored: String?) -> [LibrarySection] {
        guard let stored, !stored.isEmpty else {
            return LibrarySection.allCases.filter(isReorderableLibrarySection)
        }
        var seen = Set<LibrarySection>()
        let decoded = stored.split(separator: "\n").compactMap { LibrarySection(rawValue: String($0)) }
        return decoded.filter { isReorderableLibrarySection($0) && seen.insert($0).inserted }
    }

    func changeActivityKind(_ kind: LibraryActivityKind?) {
        activityKindFilter = kind
        loadCurrentPage(reset: true)
    }

    func setActivityCategoryFilter(_ category: ActivityLogCategoryFilter) {
        activityCategoryFilter = category
        loadCurrentPage(reset: true)
    }

    func runMetadataAnalysis() {
        metadataAnalysisTask?.cancel()
        isAnalyzingMetadata = true
        metadataAnalysisProgress = .idle
        metadataAnalysisTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await metadataAnalyzer.analyze { progress in
                    Task { @MainActor [weak self] in self?.metadataAnalysisProgress = progress }
                }
                refreshMetadataDiagnostics()
                if diagnosticKind == .suspectedVariations { loadCurrentPage(reset: true) }
            } catch is CancellationError {
                // Partial terms are safe and will be replaced by the next run.
            } catch {
                errorMessage = error.localizedDescription
            }
            isAnalyzingMetadata = false
        }
    }

    func cancelMetadataAnalysis() { metadataAnalysisTask?.cancel() }

    func ignoreVariation(_ candidate: MetadataVariationCandidate) {
        Task {
            do {
                try await Task.detached { try self.database.ignoreMetadataVariation(id: candidate.id) }.value
                loadCurrentPage(reset: false)
                refreshMetadataDiagnostics()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func searchVariationValue(_ value: String, field: MetadataField) {
        searchTask?.cancel()
        isSearchPending = false
        searchText = ""
        changeSection(.tracks, exactFilter: ExactMetadataFilter(field: field, value: value))
    }

    func selectPlaylist(_ id: Int64) {
        if selectedPlaylistID == id && section == .playlists {
            renameSelectedPlaylist()
            return
        }
        browseReturnStack.removeAll()
        selectedIndexToken = nil
        section = .playlists
        selectedAlbum = nil
        selectedArtist = nil
        selectedGenre = nil
        selectedPlaylistID = id
        loadCurrentPage(reset: true)
    }

    func sortChanged(to newSort: TrackSort? = nil) {
        usesDirectOffsetPaging = false
        selectedIndexToken = nil
        if let newSort {
            if sort == newSort { sortDirection = sortDirection == .ascending ? .descending : .ascending }
            else { sort = newSort; sortDirection = .ascending }
        }
        loadCurrentPage(reset: true)
    }

    func albumSortChanged(to newSort: AlbumSort? = nil) {
        usesDirectOffsetPaging = false
        selectedIndexToken = nil
        if let newSort {
            if albumSort == newSort { albumSortDirection = albumSortDirection == .ascending ? .descending : .ascending }
            else { albumSort = newSort; albumSortDirection = .ascending }
        }
        loadCurrentPage(reset: true)
    }

    func artistSortChanged(to newSort: ArtistSort? = nil) {
        usesDirectOffsetPaging = false
        selectedIndexToken = nil
        if let newSort {
            if artistSort == newSort { artistSortDirection = artistSortDirection == .ascending ? .descending : .ascending }
            else { artistSort = newSort; artistSortDirection = .ascending }
        }
        loadCurrentPage(reset: true)
    }

    func openAlbum(_ album: AlbumSummary) {
        captureBrowseReturnState()
        usesDirectOffsetPaging = false
        selectedIndexToken = nil
        selectedAlbum = album
        sort = .album
        sortDirection = .ascending
        loadCurrentPage(reset: true)
    }

    func openGenre(_ genre: String) {
        captureBrowseReturnState()
        usesDirectOffsetPaging = false
        selectedIndexToken = nil
        selectedGenre = genre
        selectedAlbum = nil
        selectedArtist = nil
        genreDetailMode = .albums
        loadCurrentPage(reset: true)
    }

    func changeGenreDetailMode(_ mode: GenreDetailMode) {
        genreDetailMode = mode
        selectedIndexToken = nil
        loadCurrentPage(reset: true)
    }

    func openArtist(_ artist: ArtistSummary) {
        captureBrowseReturnState()
        let requestedSection = section
        usesDirectOffsetPaging = false
        selectedIndexToken = nil
        selectedArtist = artist
        selectedAlbum = nil
        loadCurrentPage(reset: true)
        Task {
            if let exact = try? await Task.detached(operation: { try self.database.artistSummary(named: artist.name) }).value {
                // The lookup may finish after the user has moved to diagnostics
                // or another section. Never resurrect a stale detail header.
                guard section == requestedSection, selectedArtist?.name == artist.name else { return }
                selectedArtist = exact
            }
        }
    }

    func openArtist(named name: String) {
        openArtist(ArtistSummary(name: name, albumCount: 0, trackCount: 0))
    }

    func closeDetail() {
        if restoreBrowseReturnState() {
            loadCurrentPage(reset: false)
        } else {
            if selectedAlbum != nil { selectedAlbum = nil }
            else if selectedArtist != nil { selectedArtist = nil }
            else { selectedGenre = nil }
            selectedIndexToken = nil
            loadCurrentPage(reset: true)
        }
    }

    private func captureBrowseReturnState() {
        browseReturnStack.append(BrowseReturnState(
            section: section,
            sort: sort,
            sortDirection: sortDirection,
            searchText: searchText,
            selectedPlaylistID: selectedPlaylistID,
            selectedAlbum: selectedAlbum,
            selectedArtist: selectedArtist,
            selectedGenre: selectedGenre,
            genreDetailMode: genreDetailMode,
            offset: offset,
            trackPageCursors: trackPageCursors,
            usesDirectOffsetPaging: usesDirectOffsetPaging,
            selectedTrackIDs: selectedTrackIDs,
            selectedIndexToken: selectedIndexToken
        ))
        if browseReturnStack.count > 32 { browseReturnStack.removeFirst() }
    }

    @discardableResult
    private func restoreBrowseReturnState() -> Bool {
        guard let state = browseReturnStack.popLast() else { return false }
        section = state.section
        sort = state.sort
        sortDirection = state.sortDirection
        searchText = state.searchText
        selectedPlaylistID = state.selectedPlaylistID
        selectedAlbum = state.selectedAlbum
        selectedArtist = state.selectedArtist
        selectedGenre = state.selectedGenre
        genreDetailMode = state.genreDetailMode
        offset = state.offset
        trackPageCursors = state.trackPageCursors
        usesDirectOffsetPaging = state.usesDirectOffsetPaging
        selectedTrackIDs = state.selectedTrackIDs
        selectedIndexToken = state.selectedIndexToken
        return true
    }

    func genreDetailTitle(_ mode: GenreDetailMode) -> String {
        switch mode {
        case .albums: text("アルバム", "Albums")
        case .artists: text("アーティスト", "Artists")
        case .tracks: text("曲", "Songs")
        }
    }

    func savePresentationSettings() {
        do {
            try database.setSetting(language.rawValue, forKey: "app.language")
            try database.setSetting(appearance.rawValue, forKey: "app.appearance")
        } catch { errorMessage = error.localizedDescription }
    }

    func saveAISettings(openAIAPIKey: String, openAIModel: String, geminiAPIKey: String, geminiModel: String) {
        let trimmedOpenAIKey = openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGeminiKey = geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOpenAIModel = openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGeminiModel = geminiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if !trimmedOpenAIKey.isEmpty {
                try openAIKeychain.save(trimmedOpenAIKey)
                try database.setSetting("true", forKey: "openai.keyConfigured")
            }
            if !trimmedGeminiKey.isEmpty {
                try geminiKeychain.save(trimmedGeminiKey)
                try database.setSetting("true", forKey: "gemini.keyConfigured")
            }
            self.openAIModel = trimmedOpenAIModel.isEmpty ? "gpt-5.6-luna" : trimmedOpenAIModel
            self.geminiModel = trimmedGeminiModel.isEmpty ? "gemini-3.5-flash" : trimmedGeminiModel
            try database.setSetting(self.openAIModel, forKey: "openai.model")
            try database.setSetting(self.geminiModel, forKey: "gemini.model")
            if !trimmedOpenAIKey.isEmpty { hasOpenAIAPIKey = true }
            if !trimmedGeminiKey.isEmpty { hasGeminiAPIKey = true }
            refreshAIProviderStates(allowAuthenticationUI: true, validateRemotely: true)
        } catch { errorMessage = error.localizedDescription }
    }

    func removeOpenAIAPIKey() {
        do {
            try openAIKeychain.delete()
            try database.setSetting("false", forKey: "openai.keyConfigured")
            hasOpenAIAPIKey = false
            genreSuggestion = nil
            openAIStatus = .notConfigured
        } catch { errorMessage = error.localizedDescription }
    }

    func removeGeminiAPIKey() {
        do {
            try geminiKeychain.delete()
            try database.setSetting("false", forKey: "gemini.keyConfigured")
            hasGeminiAPIKey = false
            geminiStatus = .notConfigured
            genreSuggestion = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func validateAIProviders() {
        refreshAIProviderStates(allowAuthenticationUI: true, validateRemotely: true)
    }

    func classifyGenre(for track: Track) {
        guard !isClassifyingGenre else { return }
        isClassifyingGenre = true
        genreSuggestion = nil
        aiFallbackMessage = nil
        let openAIModel = openAIModel
        let geminiModel = geminiModel
        let languageCode = language.rawValue
        Task { [weak self] in
            guard let self else { return }
            let openKeychain = openAIKeychain
            let googleKeychain = geminiKeychain
            async let openAIRead = Task.detached { openKeychain.readResult(allowAuthenticationUI: true) }.value
            async let geminiRead = Task.detached { googleKeychain.readResult(allowAuthenticationUI: true) }.value
            let reads = await (openAIRead, geminiRead)
            var failures: [String] = []

            let openAIKey: String?
            switch reads.0 {
            case let .value(key): openAIKey = key
            case .authenticationRequired:
                openAIKey = nil
                openAIStatus = .configured
                failures.append("OpenAI Keychain: authentication required")
            case let .failure(message):
                openAIKey = nil
                openAIStatus = .invalid(message)
                failures.append("OpenAI Keychain: \(message)")
            }

            let geminiKey: String?
            switch reads.1 {
            case let .value(key): geminiKey = key
            case .authenticationRequired:
                geminiKey = nil
                geminiStatus = .configured
                failures.append("Gemini Keychain: authentication required")
            case let .failure(message):
                geminiKey = nil
                geminiStatus = .invalid(message)
                failures.append("Gemini Keychain: \(message)")
            }

            if let key = openAIKey, !key.isEmpty {
                do {
                    genreSuggestion = try await genreClassifier.classify(
                        track: track, apiKey: key, model: openAIModel, language: languageCode
                    )
                    openAIStatus = .valid
                    isClassifyingGenre = false
                    return
                } catch {
                    let summary = providerErrorSummary(error)
                    openAIStatus = .invalid(summary)
                    failures.append("OpenAI: \(summary)")
                }
            }

            if let key = geminiKey, !key.isEmpty {
                do {
                    genreSuggestion = try await geminiGenreClassifier.classify(
                        track: track, apiKey: key, model: geminiModel, language: languageCode
                    )
                    geminiStatus = .valid
                    if !failures.isEmpty {
                        aiFallbackMessage = text(
                            "OpenAIで失敗したためGeminiへ切り替えました。\(failures.joined(separator: " / "))",
                            "OpenAI failed, so Gemini was used. \(failures.joined(separator: " / "))"
                        )
                    }
                    isClassifyingGenre = false
                    return
                } catch {
                    let summary = providerErrorSummary(error)
                    geminiStatus = .invalid(summary)
                    failures.append("Gemini: \(summary)")
                }
            }

            genreSuggestion = localSuggestion(for: track)
            if !failures.isEmpty {
                aiFallbackMessage = text(
                    "外部AIが失敗したため内蔵AIを使用しました。\(failures.joined(separator: " / "))",
                    "External AI failed, so the built-in AI was used. \(failures.joined(separator: " / "))"
                )
            }
            isClassifyingGenre = false
        }
    }

    private func refreshAIProviderStates(allowAuthenticationUI: Bool, validateRemotely: Bool) {
        refreshOpenAIProviderState(
            allowAuthenticationUI: allowAuthenticationUI,
            validateRemotely: validateRemotely
        )
        refreshGeminiProviderState(
            allowAuthenticationUI: allowAuthenticationUI,
            validateRemotely: validateRemotely
        )
    }

    /// Restores only non-secret display state during launch. Reading Keychain items here
    /// would allow macOS to present an authentication dialog before the user requested AI.
    private func restoreAIProviderConfigurationWithoutReadingKeys() {
        hasOpenAIAPIKey = (try? database.setting(forKey: "openai.keyConfigured")) == "true"
        hasGeminiAPIKey = (try? database.setting(forKey: "gemini.keyConfigured")) == "true"
        openAIStatus = hasOpenAIAPIKey ? .configured : .notConfigured
        geminiStatus = hasGeminiAPIKey ? .configured : .notConfigured
    }

    private func refreshOpenAIProviderState(allowAuthenticationUI: Bool, validateRemotely: Bool) {
        let keychain = openAIKeychain
        Task { [weak self] in
            guard let self else { return }
            let result = await Task.detached {
                keychain.readResult(allowAuthenticationUI: allowAuthenticationUI)
            }.value
            guard !Task.isCancelled else { return }
            let key: String?
            switch result {
            case let .value(value): key = value
            case .authenticationRequired:
                hasOpenAIAPIKey = true
                openAIStatus = .configured
                return
            case let .failure(message):
                openAIStatus = .invalid(message)
                return
            }
            hasOpenAIAPIKey = key?.isEmpty == false
            guard let key, !key.isEmpty else { openAIStatus = .notConfigured; return }
            guard validateRemotely else { openAIStatus = .configured; return }
            openAIStatus = .checking
            do {
                try await genreClassifier.validate(apiKey: key)
                openAIStatus = .valid
            } catch {
                openAIStatus = .invalid(providerErrorSummary(error))
            }
        }
    }

    private func refreshGeminiProviderState(allowAuthenticationUI: Bool, validateRemotely: Bool) {
        let keychain = geminiKeychain
        let model = geminiModel
        Task { [weak self] in
            guard let self else { return }
            let result = await Task.detached {
                keychain.readResult(allowAuthenticationUI: allowAuthenticationUI)
            }.value
            guard !Task.isCancelled else { return }
            let key: String?
            switch result {
            case let .value(value): key = value
            case .authenticationRequired:
                hasGeminiAPIKey = true
                geminiStatus = .configured
                return
            case let .failure(message):
                geminiStatus = .invalid(message)
                return
            }
            hasGeminiAPIKey = key?.isEmpty == false
            guard let key, !key.isEmpty else { geminiStatus = .notConfigured; return }
            guard validateRemotely else { geminiStatus = .configured; return }
            geminiStatus = .checking
            do {
                try await geminiGenreClassifier.validate(apiKey: key, model: model)
                geminiStatus = .valid
            } catch {
                geminiStatus = .invalid(providerErrorSummary(error))
            }
        }
    }

    private func localSuggestion(for track: Track) -> GenreSuggestion {
        let prediction = localGenreClassifier.classify(track: track)
        let evidence = prediction.matchedTerms.joined(separator: "、")
        let rationale = prediction.matchedTerms.isEmpty
            ? text("内蔵AIがメタデータを確認しましたが、明確な手掛かりがないため低い確信度でOtherを提案しました。", "The built-in AI found no clear metadata clue, so it suggested Other with low confidence.")
            : text("内蔵AIがメタデータ内の「\(evidence)」を手掛かりに判定しました。音声は解析していません。", "The built-in AI used \(evidence) found in the metadata. Audio was not analyzed.")
        return GenreSuggestion(
            genre: prediction.genre,
            confidence: prediction.confidence,
            rationale: rationale,
            source: .local
        )
    }

    private func providerErrorSummary(_ error: Error) -> String {
        String(error.localizedDescription.prefix(160))
    }

    func applyGenreSuggestion(to track: Track) {
        guard let genreSuggestion else { return }
        self.genreSuggestion = nil
        let genre = genreSuggestion.genre
        Task { [weak self] in
            guard let self else { return }
            do {
                // Register the result first. A cached song remains editable even
                // while its external source drive is disconnected.
                try await Task.detached {
                    try self.database.updateTrackGenre(id: track.id, genre: genre)
                }.value

                // Keep the source tag in sync when the original really exists.
                // Missing media is an offline state, not a failed AI operation.
                if await trackFiles.sourceFileIsAvailable(for: track) {
                    var edit = TrackMetadataEdit(track: track)
                    edit.genre = genre
                    try await updateMetadataAsync(for: track, edit: edit)
                } else {
                    loadCurrentPage(reset: false)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func clearGenreSuggestion() { genreSuggestion = nil }

    func saveManualLyrics(for track: Track, lyrics: String) {
        let trimmedLyrics = lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLyrics.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.detached {
                    try self.database.saveLyrics(
                        trackID: track.id,
                        provider: "Manual",
                        plain: trimmedLyrics,
                        synced: nil
                    )
                }.value
                enrich(track)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func appearanceTitle(_ mode: AppearanceMode) -> String {
        switch mode {
        case .system: text("システム設定", "System")
        case .light: text("ライト", "Light")
        case .dark: text("ダーク", "Dark")
        }
    }

    func newsURL(for artist: String) -> URL? {
        var components = URLComponents(string: "https://news.google.com/search")
        let languageParameters = language == .japanese
            ? (hl: "ja", gl: "JP", ceid: "JP:ja")
            : (hl: "en-US", gl: "US", ceid: "US:en")
        components?.queryItems = [
            URLQueryItem(name: "q", value: artist),
            URLQueryItem(name: "hl", value: languageParameters.hl),
            URLQueryItem(name: "gl", value: languageParameters.gl),
            URLQueryItem(name: "ceid", value: languageParameters.ceid)
        ]
        return components?.url
    }

    func youtubeURL(for track: Track) -> URL? {
        var components = URLComponents(string: "https://www.youtube.com/results")
        components?.queryItems = [
            URLQueryItem(name: "search_query", value: "\(track.artist) \(track.title)")
        ]
        return components?.url
    }

    func albumWikipediaURL(for track: Track) -> URL? {
        guard !track.album.isEmpty else { return nil }
        let host = language == .japanese ? "ja.wikipedia.org" : "en.wikipedia.org"
        var components = URLComponents(string: "https://\(host)/w/index.php")
        let query = track.artist.isEmpty ? track.album : "\(track.artist) \(track.album)"
        components?.queryItems = [
            URLQueryItem(name: "search", value: query)
        ]
        return components?.url
    }

    func albumGoogleURL(for track: Track) -> URL? {
        guard !track.album.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.google.com/search")
        let query = track.artist.isEmpty ? track.album : "\(track.artist) \(track.album)"
        components?.queryItems = [
            URLQueryItem(name: "q", value: query)
        ]
        return components?.url
    }
    func previousPage() {
        guard offset > 0 else { return }
        if usesKeysetPaging, !usesDirectOffsetPaging, trackPageCursors.count > 1 { trackPageCursors.removeLast() }
        offset = max(0, offset - activePageSize)
        loadCurrentPage(reset: false)
    }
    func nextPage() {
        if usesKeysetPaging, !usesDirectOffsetPaging { trackPageCursors.append(tracks.last) }
        offset += activePageSize
        loadCurrentPage(reset: false)
    }

    func goToPage(_ page: Int) {
        guard pageCount > 0 else { return }
        let clamped = min(pageCount, max(1, page))
        offset = (clamped - 1) * activePageSize
        if usesKeysetPaging {
            usesDirectOffsetPaging = true
            trackPageCursors = [nil]
        }
        loadCurrentPage(reset: false)
    }

    func jumpToIndex(_ value: String) {
        guard let target = alphabetIndexTarget else { return }
        selectedIndexToken = value
        let album = selectedAlbum
        let artist = selectedArtist
        let genre = selectedGenre
        let requestedSearch = searchText
        if target == .tracks {
            sort = .title
            sortDirection = .ascending
            searchText = ""
            usesDirectOffsetPaging = true
            trackPageCursors = [nil]
        }
        isLoading = true
        Task {
            do {
                let newOffset = try await Task.detached(priority: .userInitiated) {
                    switch target {
                    case .tracks:
                        return try self.database.offsetForTrackTitle(
                            startingAt: value,
                            albumFilter: album,
                            artistFilter: artist?.name,
                            genreFilter: genre,
                            availableOnly: album != nil || artist != nil || genre != nil
                        )
                    case .albums:
                        return try self.database.offsetForAlbum(
                            startingAt: value,
                            artistFilter: artist?.name,
                            genreFilter: genre
                        )
                    case .artists:
                        return try self.database.offsetForArtist(startingAt: value, genreFilter: genre, search: requestedSearch)
                    }
                }.value
                offset = newOffset
                loadCurrentPage(reset: false)
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    func loadCurrentPage(reset: Bool) {
        pageLoadTask?.cancel()
        if reset {
            offset = 0
            trackPageCursors = [nil]
        }
        let requestedOffset = offset
        let requestedSection = section
        let requestedQuery = searchText
        let requestedSort = sort
        let requestedDirection = sortDirection
        let requestedAlbumSort = albumSort
        let requestedAlbumDirection = albumSortDirection
        let requestedArtistSort = artistSort
        let requestedArtistDirection = artistSortDirection
        let playlistID = selectedPlaylistID
        let pageCursor = trackPageCursors.last ?? nil
        let knownTotal = requestedOffset == 0 ? nil : totalCount
        let requestedDiagnosticKind = diagnosticKind
        let requestedActivityKind = activityKindFilter
        let requestedCategoryKinds = activityCategoryFilter.kinds
        let requestedGenre = selectedGenre
        let requestedGenreMode = genreDetailMode
        let requestedAlbum = selectedAlbum
        let requestedArtist = selectedArtist
        let requestedExactMetadataFilter = exactMetadataFilter
        let requestedStorageScope: String?
        if requestedExactMetadataFilter != nil {
            // An exact diagnostic value is not the whole library. The filtered
            // row count is shown by the page itself; hide the unrelated global
            // capacity/path summary until an exact storage aggregation exists.
            requestedStorageScope = nil
        } else if let requestedAlbum {
            requestedStorageScope = "album:\(requestedAlbum.id)"
        } else if let requestedArtist {
            requestedStorageScope = "artist:\(requestedArtist.name)"
        } else if [.tracks, .recentlyAdded, .albums, .artists].contains(requestedSection) {
            requestedStorageScope = "library"
        } else {
            requestedStorageScope = nil
        }
        isLoading = true
        errorMessage = nil
        pageLoadTask = Task { [weak self] in
            guard let self else { return }
            do {
                if requestedSection == .activityLog {
                    let page = try await Task.detached(priority: .userInitiated) {
                        try self.database.activityLogPage(
                            kinds: requestedActivityKind.map { [$0] } ?? requestedCategoryKinds,
                            query: requestedQuery, offset: requestedOffset, limit: self.activityPageSize
                        )
                    }.value
                    activityEvents = page.events
                    tracks = []
                    facets = []
                    albumSummaries = []
                    artistSummaries = []
                    variationCandidates = []
                    offset = page.offset
                    totalCount = page.totalCount
                } else if requestedSection == .diagnostics {
                    if requestedDiagnosticKind == .suspectedVariations {
                        let page = try await Task.detached(priority: .userInitiated) {
                            try self.database.pageMetadataVariations(offset: requestedOffset, limit: self.pageSize)
                        }.value
                        variationCandidates = page.candidates
                        activityEvents = []
                        tracks = []
                        facets = []
                        albumSummaries = []
                        artistSummaries = []
                        offset = page.offset
                        totalCount = page.totalCount
                    } else {
                        let page = try await Task.detached(priority: .userInitiated) {
                            try self.database.pageMetadataIssues(
                                kind: requestedDiagnosticKind, sort: requestedSort, direction: requestedDirection,
                                offset: requestedOffset, limit: self.pageSize
                            )
                        }.value
                        apply(page: page)
                        updateDiagnosticSummary(kind: requestedDiagnosticKind, count: page.totalCount)
                    }
                } else if let album = requestedAlbum {
                    let page = try await Task.detached(priority: .userInitiated) {
                        try self.database.pageTracksForAlbum(
                            album: album, sort: requestedSort, direction: requestedDirection,
                            offset: requestedOffset, limit: self.pageSize
                        )
                    }.value
                    try Task.checkCancellation()
                    apply(page: page)
                } else if let artist = requestedArtist {
                    if artist.name.isEmpty {
                        let page = try await Task.detached(priority: .userInitiated) {
                            try self.database.pageTracksForArtist(
                                artist: "", sort: requestedSort, direction: requestedDirection,
                                offset: requestedOffset, limit: self.pageSize
                            )
                        }.value
                        try Task.checkCancellation()
                        apply(page: page)
                    } else {
                        let page = try await Task.detached(priority: .userInitiated) {
                            try self.database.pageAlbums(
                                artistFilter: artist.name,
                                sort: requestedAlbumSort,
                                direction: requestedAlbumDirection,
                                offset: requestedOffset,
                                limit: self.pageSize
                            )
                        }.value
                        try Task.checkCancellation()
                        apply(albumPage: page)
                    }
                } else if let genre = requestedGenre {
                    switch requestedGenreMode {
                    case .albums:
                        let page = try await Task.detached(priority: .userInitiated) {
                            try self.database.pageAlbums(
                                genreFilter: genre,
                                sort: requestedAlbumSort,
                                direction: requestedAlbumDirection,
                                offset: requestedOffset,
                                limit: self.pageSize
                            )
                        }.value
                        apply(albumPage: page)
                    case .artists:
                        let page = try await Task.detached(priority: .userInitiated) {
                            try self.database.pageArtists(
                                genreFilter: genre,
                                search: requestedQuery,
                                sort: requestedArtistSort,
                                direction: requestedArtistDirection,
                                offset: requestedOffset,
                                limit: self.pageSize
                            )
                        }.value
                        apply(artistPage: page)
                    case .tracks:
                        let page = try await Task.detached(priority: .userInitiated) {
                            try self.database.pageTracksForGenre(
                                genre: genre, sort: requestedSort, direction: requestedDirection,
                                offset: requestedOffset, limit: self.pageSize
                            )
                        }.value
                        apply(page: page)
                    }
                } else if let requestedExactMetadataFilter, requestedSection == .tracks {
                    let page = try await Task.detached(priority: .userInitiated) {
                        try self.database.pageTracks(
                            matching: requestedExactMetadataFilter,
                            sort: requestedSort, direction: requestedDirection,
                            offset: requestedOffset, limit: self.pageSize
                        )
                    }.value
                    try Task.checkCancellation()
                    apply(page: page)
                } else if requestedSection == .albums {
                    let page = try await Task.detached(priority: .userInitiated) {
                        try self.database.pageAlbums(
                            sort: requestedAlbumSort,
                            direction: requestedAlbumDirection,
                            offset: requestedOffset,
                            limit: self.pageSize
                        )
                    }.value
                    try Task.checkCancellation()
                    apply(albumPage: page)
                } else if requestedSection == .artists {
                    let page = try await Task.detached(priority: .userInitiated) {
                        try self.database.pageArtists(
                            search: requestedQuery,
                            sort: requestedArtistSort,
                            direction: requestedArtistDirection,
                            offset: requestedOffset,
                            limit: self.pageSize
                        )
                    }.value
                    try Task.checkCancellation()
                    apply(artistPage: page)
                } else if requestedSection == .favorites {
                    let page = try await Task.detached(priority: .userInitiated) {
                        try self.database.pageFavoriteTracks(
                            sort: requestedSort, direction: requestedDirection,
                            offset: requestedOffset, limit: self.pageSize
                        )
                    }.value
                    apply(page: page)
                } else if requestedSection == .recentlyAdded {
                    let page: TrackPage
                    if usesDirectOffsetPaging {
                        page = try await Task.detached(priority: .userInitiated) {
                            try self.database.pageTracks(
                                query: requestedQuery, sort: requestedSort, direction: requestedDirection,
                                offset: requestedOffset, limit: self.pageSize
                            )
                        }.value
                    } else {
                        page = try await Task.detached(priority: .userInitiated) {
                            try self.database.pageTracksAfter(
                                query: requestedQuery, sort: requestedSort, direction: requestedDirection,
                                after: pageCursor, logicalOffset: requestedOffset, limit: self.pageSize,
                                knownTotal: knownTotal
                            )
                        }.value
                    }
                    try Task.checkCancellation()
                    apply(page: page)
                } else if requestedSection == .cache {
                    let page = try await Task.detached(priority: .userInitiated) {
                        try self.database.pageCachedTracks(
                            query: requestedQuery, sort: requestedSort, direction: requestedDirection,
                            offset: requestedOffset, limit: self.pageSize
                        )
                    }.value
                    apply(page: page)
                } else if requestedSection == .playlists, let playlistID {
                    let page = try await Task.detached(priority: .userInitiated) {
                        try self.database.playlistTracks(
                            playlistID: playlistID, offset: requestedOffset, limit: self.pageSize,
                            sort: requestedSort, direction: requestedDirection
                        )
                    }.value
                    apply(page: page)
                } else if [.genres, .folders].contains(requestedSection) {
                    let page = try await Task.detached(priority: .userInitiated) {
                        try self.database.facetPage(
                            section: requestedSection, offset: requestedOffset, limit: self.pageSize
                        )
                    }.value
                    facets = page.facets
                    tracks = []
                    activityEvents = []
                    offset = page.offset
                    totalCount = page.totalCount
                } else {
                    let page: TrackPage
                    if usesDirectOffsetPaging {
                        page = try await Task.detached(priority: .userInitiated) {
                            try self.database.pageTracks(
                                query: requestedQuery, sort: requestedSort, direction: requestedDirection,
                                offset: requestedOffset, limit: self.pageSize
                            )
                        }.value
                    } else {
                        page = try await Task.detached(priority: .userInitiated) {
                            try self.database.pageTracksAfter(
                                query: requestedQuery, sort: requestedSort, direction: requestedDirection, after: pageCursor,
                                logicalOffset: requestedOffset, limit: self.pageSize,
                                knownTotal: knownTotal
                            )
                        }.value
                    }
                    apply(page: page)
                }
                try Task.checkCancellation()
                let visibleTrackIDs = tracks.map(\.id)
                cachedTrackIDs = try await Task.detached(priority: .utility) {
                    try self.database.cachedTrackIDs(in: visibleTrackIDs)
                }.value
                await refreshVisibleTrackAvailability()
                if let requestedStorageScope {
                    if headerStorageScope != requestedStorageScope || headerStorageSummary == nil {
                        headerStorageSummary = try await Task.detached(priority: .utility) {
                            try self.database.libraryStorageSummary(
                                albumFilter: requestedAlbum,
                                artistFilter: requestedAlbum == nil ? requestedArtist?.name : nil
                            )
                        }.value
                        headerStorageScope = requestedStorageScope
                    }
                } else {
                    headerStorageSummary = nil
                    headerStorageScope = nil
                }
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
            guard !Task.isCancelled else { return }
            isLoading = false
        }
    }

    func chooseAndScanFolder() {
        let panel = NSOpenPanel()
        panel.title = text("音楽フォルダを選択", "Choose Music Folder")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        startScan(url: url)
    }

    func startScan(url: URL) {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let scoped = try SecurityScopedRoot.create(for: url)
                let values = try url.resourceValues(forKeys: [.volumeUUIDStringKey, .nameKey])
                let rootID = try await Task.detached {
                    try self.database.addScanRoot(
                        displayName: values.name ?? url.lastPathComponent,
                        bookmark: scoped.bookmark,
                        volumeUUID: values.volumeUUIDString,
                        path: url.path
                    )
                }.value
                try await scanner.scan(root: scoped, rootID: rootID) { [weak self] progress in
                    Task { @MainActor in
                        self?.scanProgress = progress
                        if progress.state == .completed {
                            self?.headerStorageScope = nil
                            self?.loadCurrentPage(reset: true)
                            self?.startLeadingTitleSpaceCleanup()
                        }
                    }
                }
            } catch is CancellationError {
                await scanner.cancel()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func pauseScan() { Task { await scanner.pause() } }
    func resumeScan() { Task { await scanner.resume() } }
    func cancelScan() { Task { await scanner.cancel() } }

    var localCacheDirectoryPath: String {
        if !isStorageExternal, let primary = storageDestinations.first(where: \.isPrimary) {
            return primary.path
        }
        return OfflineCacheManager.cacheDirectoryURL().path
    }

    func isCached(_ track: Track) -> Bool {
        section == .cache || cachedTrackIDs.contains(track.id)
    }

    func isTrackPlayable(_ track: Track) -> Bool {
        isCached(track) || (
            track.isAvailable
                && !unavailableRootIDs.contains(track.rootID)
                && !missingVisibleTrackIDs.contains(track.id)
        )
    }

    private func refreshVisibleTrackAvailability() async {
        let visibleTracks = tracks
        let cachedIDs = cachedTrackIDs
        guard !visibleTracks.isEmpty else {
            missingVisibleTrackIDs = []
            return
        }
        missingVisibleTrackIDs = await Task.detached(priority: .utility) {
            let roots = (try? self.database.scanRoots()) ?? []
            let neededRootIDs = Set(visibleTracks.lazy.filter { !cachedIDs.contains($0.id) }.map(\.rootID))
            var rootURLs: [Int64: URL] = [:]
            var accessedURLs: [URL] = []
            defer {
                for url in accessedURLs { url.stopAccessingSecurityScopedResource() }
            }
            for root in roots where neededRootIDs.contains(root.id) {
                guard let scoped = try? SecurityScopedRoot.resolve(bookmark: root.bookmark),
                      FileManager.default.fileExists(atPath: scoped.url.path) else { continue }
                if scoped.url.startAccessingSecurityScopedResource() {
                    accessedURLs.append(scoped.url)
                }
                rootURLs[root.id] = scoped.url
            }
            return Set(visibleTracks.lazy.compactMap { track -> Int64? in
                guard !cachedIDs.contains(track.id) else { return nil }
                guard let rootURL = rootURLs[track.rootID] else { return track.id }
                let sourceURL = rootURL.appending(path: track.relativePath)
                return FileManager.default.fileExists(atPath: sourceURL.path) ? nil : track.id
            })
        }.value
    }

    func cacheTrack(_ track: Track) {
        guard !isCached(track), !cachingTrackIDs.contains(track.id) else { return }
        if cacheTrackLimit == 0 {
            cacheTrackLimit = 1
            saveCacheSettings()
        }
        cachingTrackIDs.insert(track.id)
        Task {
            defer { cachingTrackIDs.remove(track.id) }
            do {
                _ = try await offlineCache.cacheExplicitly(track)
                cachedTrackIDs.insert(track.id)
                if section == .cache { loadCurrentPage(reset: true) }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func removeTrackFromCache(_ track: Track) {
        Task {
            do {
                try await offlineCache.remove(trackID: track.id)
                cachedTrackIDs.remove(track.id)
                if section == .cache { loadCurrentPage(reset: false) }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func setFavorite(_ track: Track, isFavorite: Bool, cacheLocally: Bool = false) {
        Task {
            do {
                try await Task.detached {
                    try self.database.setFavorite(trackID: track.id, isFavorite: isFavorite)
                }.value
                do {
                    if isFavorite, cacheLocally {
                        _ = try await offlineCache.cacheForFavorite(track)
                    } else if !isFavorite {
                        try await offlineCache.unpin(trackID: track.id)
                    }
                } catch {
                    loadCurrentPage(reset: false)
                    throw error
                }
                loadCurrentPage(reset: false)
                refreshSidebarCounts()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func revealLocalCache() {
        let url = URL(filePath: localCacheDirectoryPath, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func refreshStorageSyncHistory() {
        Task { [weak self] in
            guard let self else { return }
            let page = try? await Task.detached(priority: .utility) {
                try self.database.activityLogPage(
                    kinds: [.addedToCache, .addedToMainStorage], offset: 0, limit: 20
                )
            }.value
            storageSyncEvents = page?.events ?? []
        }
    }

    func loadArtwork(for album: AlbumSummary) {
        guard albumArtworkURLs[album.id] == nil, loadingAlbumArtworkIDs.insert(album.id).inserted else { return }
        Task { [weak self] in
            guard let self else { return }
            let url = await enrichment.albumArtworkURL(album: album.name, artist: album.artist)
            loadingAlbumArtworkIDs.remove(album.id)
            if let url { albumArtworkURLs[album.id] = url }
        }
    }

    func loadImage(for artist: ArtistSummary) {
        let name = artist.name
        guard !name.isEmpty, artistImageURLs[name] == nil, loadingArtistImageNames.insert(name).inserted else { return }
        Task { [weak self] in
            guard let self else { return }
            let url = await enrichment.artistImageURL(artist: name, languageCode: language.rawValue)
            loadingArtistImageNames.remove(name)
            if let url { artistImageURLs[name] = url }
        }
    }
    func updateMetadata(for track: Track, edit: TrackMetadataEdit) {
        Task {
            _ = await updateMetadataFromEditor(for: track, edit: edit)
        }
    }

    /// Saves one editor page and reports whether navigation may continue.
    /// Repairable MP3 errors open the existing confirmation flow and keep the editor on the current track.
    func updateMetadataFromEditor(for track: Track, edit: TrackMetadataEdit) async -> Bool {
        do {
            try await updateMetadataAsync(for: track, edit: edit)
            return true
        } catch {
            let repairableID3Damage = (error as? MassiveMusicError)?.isRepairableID3Damage == true
                || error.localizedDescription.contains("ID3フレーム")
                || error.localizedDescription.contains("ID3タグ")
            if track.format.lowercased() == "mp3", repairableID3Damage {
                metadataRepairRequest = MetadataRepairRequest(track: track, edit: edit)
            } else {
                errorMessage = error.localizedDescription
            }
            return false
        }
    }

    func updateMetadataAsync(for track: Track, edit: TrackMetadataEdit) async throws {
        let sourceFileIsAvailable = await trackFiles.sourceFileIsAvailable(for: track)
        if !sourceFileIsAvailable {
            try await queueMetadataEditForLater(track: track, edit: edit)
            return
        }
        try await runFileOperationWithAuthorizationRetry(for: track) {
            try await self.trackFiles.updateMetadata(track: track, edit: edit, authorizedRoot: $0)
        }
        handleCompletedMetadataEdit(for: track, edit: edit)
    }

    private func queueMetadataEditForLater(track: Track, edit: TrackMetadataEdit) async throws {
        let normalized = edit.normalizingLeadingTitleSpaces()
        try await Task.detached {
            try self.database.queuePendingMetadataEdit(
                id: track.id,
                edit: normalized,
                fileSize: track.fileSize,
                modifiedAt: track.modifiedAt
            )
        }.value
        handleCompletedMetadataEdit(for: track, edit: normalized)
    }

    private func handleCompletedMetadataEdit(for track: Track, edit: TrackMetadataEdit) {
        let editedAlbumIdentity = AlbumSummary(
            name: edit.album,
            artist: edit.albumArtist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? edit.artist : edit.albumArtist,
            trackCount: 0
        ).id
        if let selectedAlbum, selectedAlbum.id != editedAlbumIdentity {
            // The open detail points at the old metadata value. Keeping it open
            // would show a misleading empty album after a successful rename.
            // Use the browse return state so page, query, sort and index jump
            // are restored instead of sending the user to the first page.
            closeDetail()
        } else {
            loadCurrentPage(reset: false)
        }
        if edit.artworkData != nil { refreshEnrichmentIfNeeded(updatedTrackIDs: [track.id]) }
        refreshSidebarCounts()
    }

    func confirmMetadataRepair() {
        guard let request = metadataRepairRequest else { return }
        metadataRepairRequest = nil
        Task {
            do {
                try await runFileOperationWithAuthorizationRetry(for: request.track) {
                    try await self.trackFiles.updateMetadata(
                        track: request.track,
                        edit: request.edit,
                        authorizedRoot: $0,
                        repairingCorruptID3: true
                    )
                }
                loadCurrentPage(reset: false)
                if request.edit.artworkData != nil {
                    refreshEnrichmentIfNeeded(updatedTrackIDs: [request.track.id])
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func webMetadataCandidates(for track: Track) async throws -> [MusicMetadataCandidate] {
        try await musicMetadata.candidates(for: track)
    }

    func albumTrackCount(album: String, artist: String) async -> Int {
        (try? await Task.detached {
            try self.database.albumTrackCount(album: album, artist: artist)
        }.value) ?? 0
    }

    func updateMetadata(for tracks: [Track], changes: BatchMetadataChanges) {
        guard !tracks.isEmpty, !changes.isEmpty, batchMetadataProgress.state != .running else { return }
        batchMetadataTask?.cancel()
        batchMetadataProgress = BatchMetadataProgress(state: .running, total: tracks.count)
        batchMetadataTask = Task { [weak self] in
            guard let self else { return }
            var succeeded = 0
            var failed = 0
            var firstError: Error?
            for (index, track) in tracks.enumerated() {
                if Task.isCancelled {
                    batchMetadataProgress = BatchMetadataProgress(
                        state: .cancelled, total: tracks.count, processed: index,
                        succeeded: succeeded, failed: failed
                    )
                    return
                }
                batchMetadataProgress = BatchMetadataProgress(
                    state: .running, total: tracks.count, processed: index,
                    succeeded: succeeded, failed: failed, currentFilename: track.filename
                )
                do {
                    let edit = changes.applying(to: track, offset: index)
                    try await runFileOperationWithAuthorizationRetry(for: track) {
                        try await self.trackFiles.updateMetadata(track: track, edit: edit, authorizedRoot: $0)
                    }
                    succeeded += 1
                } catch is CancellationError {
                    batchMetadataProgress = BatchMetadataProgress(
                        state: .cancelled, total: tracks.count, processed: index,
                        succeeded: succeeded, failed: failed
                    )
                    return
                } catch {
                    failed += 1
                    if firstError == nil { firstError = error }
                }
                batchMetadataProgress = BatchMetadataProgress(
                    state: .running, total: tracks.count, processed: index + 1,
                    succeeded: succeeded, failed: failed, currentFilename: track.filename
                )
            }
            headerStorageScope = nil
            loadCurrentPage(reset: false)
            if changes.artworkData != nil {
                refreshEnrichmentIfNeeded(updatedTrackIDs: Set(tracks.map(\.id)))
            }
            batchMetadataProgress = BatchMetadataProgress(
                state: .completed, total: tracks.count, processed: tracks.count,
                succeeded: succeeded, failed: failed
            )
            if let firstError {
                errorMessage = text(
                    "\(failed)曲の更新に失敗しました。最初のエラー: \(firstError.localizedDescription)",
                    "Failed to update \(failed) songs. First error: \(firstError.localizedDescription)"
                )
            }
        }
    }

    func cancelBatchMetadataUpdate() {
        batchMetadataTask?.cancel()
    }

    /// Repairs existing and newly scanned titles in small keyset pages. Each
    /// source file still goes through AudioMetadataWriter's copy, verify, write,
    /// verify, and rollback path before the database is updated.
    private func startLeadingTitleSpaceCleanup() {
        guard leadingTitleSpaceCleanupTask == nil else { return }
        guard allScanRootsAreConnected() else { return }
        leadingTitleSpaceCleanupTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            var afterID: Int64 = 0
            var failed = 0
            var firstError: Error?
            do {
                while !Task.isCancelled {
                    let database = self.database
                    let requestedAfterID = afterID
                    let page = try await Task.detached(priority: .utility) {
                        try database.tracksWithLeadingTitleSpaces(afterID: requestedAfterID, limit: 50)
                    }.value
                    guard !page.isEmpty else { break }
                    for track in page {
                        try Task.checkCancellation()
                        afterID = track.id
                        let edit = TrackMetadataEdit(track: track).normalizingLeadingTitleSpaces()
                        guard !edit.title.isEmpty else {
                            failed += 1
                            continue
                        }
                        do {
                            do {
                                try await self.trackFiles.updateMetadata(track: track, edit: edit)
                            } catch let error as MassiveMusicError
                                where track.format.lowercased() == "mp3" && error.isRepairableID3Damage {
                                try await self.trackFiles.updateMetadata(
                                    track: track, edit: edit, repairingCorruptID3: true
                                )
                            }
                        } catch {
                            failed += 1
                            if firstError == nil { firstError = error }
                        }
                    }
                }
                headerStorageScope = nil
                loadCurrentPage(reset: false)
                refreshMetadataDiagnostics()
                if let firstError {
                    errorMessage = text(
                        "先頭スペースの自動修正で\(failed)曲を保存できませんでした。最初のエラー: \(firstError.localizedDescription)",
                        "Could not save \(failed) songs while removing leading title spaces. First error: \(firstError.localizedDescription)"
                    )
                }
            } catch is CancellationError {
                // Remaining rows are discovered again on the next launch or completed scan.
            } catch {
                errorMessage = error.localizedDescription
            }
            leadingTitleSpaceCleanupTask = nil
            startWidthNormalization()
        }
    }

    /// Scans the library in bounded keyset pages and writes only records whose
    /// half-width kana or full-width ASCII actually changes. The persisted
    /// cursor makes the 360k-track pass resumable and prevents rescanning old
    /// rows on every launch.
    private func startWidthNormalization() {
        guard normalizeMetadataCharacterWidths, widthNormalizationTask == nil else { return }
        guard allScanRootsAreConnected() else { return }
        widthNormalizationTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            var afterID = Int64((try? database.setting(forKey: "metadata.widthNormalizationCursor")) ?? "0") ?? 0
            var failed = 0
            var firstError: Error?
            do {
                while !Task.isCancelled, normalizeMetadataCharacterWidths {
                    let requestedAfterID = afterID
                    let page = try await Task.detached(priority: .utility) {
                        try self.database.tracksForWidthNormalization(afterID: requestedAfterID, limit: 200)
                    }.value
                    guard !page.isEmpty else { break }
                    for track in page {
                        try Task.checkCancellation()
                        afterID = track.id
                        let edit = TrackMetadataEdit(track: track).normalizingCharacterWidths()
                        if edit.hasTextChanges(comparedWith: track) {
                            do {
                                do {
                                    try await trackFiles.updateMetadata(track: track, edit: edit)
                                } catch let error as MassiveMusicError
                                    where track.format.lowercased() == "mp3" && error.isRepairableID3Damage {
                                    try await trackFiles.updateMetadata(
                                        track: track, edit: edit, repairingCorruptID3: true
                                    )
                                }
                            } catch {
                                failed += 1
                                if firstError == nil { firstError = error }
                            }
                        }
                    }
                    try database.setSetting(
                        String(afterID), forKey: "metadata.widthNormalizationCursor"
                    )
                }
                headerStorageScope = nil
                loadCurrentPage(reset: false)
                refreshMetadataDiagnostics()
                if let firstError {
                    errorMessage = text(
                        "文字幅の自動修正で\(failed)曲を保存できませんでした。最初のエラー: \(firstError.localizedDescription)",
                        "Could not save \(failed) songs during character-width normalization. First error: \(firstError.localizedDescription)"
                    )
                }
            } catch is CancellationError {
                // The saved keyset cursor resumes safely when the option is enabled again.
            } catch {
                errorMessage = error.localizedDescription
            }
            widthNormalizationTask = nil
        }
    }

    private func allScanRootsAreConnected() -> Bool {
        guard let roots = try? database.scanRoots(), !roots.isEmpty else { return false }
        return roots.allSatisfy { FileManager.default.fileExists(atPath: $0.lastKnownPath) }
    }

    func resetBatchMetadataProgress() {
        guard batchMetadataProgress.state != .running else { return }
        batchMetadataProgress = .idle
        batchMetadataTask = nil
    }

    func removeFromLibrary(_ track: Track) {
        Task {
            do {
                try await trackFiles.removeFromLibrary(track: track)
                loadCurrentPage(reset: true)
                refreshPlaylists()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func moveFileToTrash(_ track: Track) {
        Task {
            do {
                try await runFileOperationWithAuthorizationRetry(for: track) {
                    try await self.trackFiles.moveFileToTrash(track: track, authorizedRoot: $0)
                }
                loadCurrentPage(reset: true)
                refreshPlaylists()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func moveFilesToTrash(_ tracks: [Track]) {
        Task {
            do {
                for track in tracks {
                    try await runFileOperationWithAuthorizationRetry(for: track) {
                        try await self.trackFiles.moveFileToTrash(track: track, authorizedRoot: $0)
                    }
                }
                loadCurrentPage(reset: true)
                refreshPlaylists()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func removeTracksFromLibrary(_ tracks: [Track]) {
        Task {
            do {
                for track in tracks {
                    try await trackFiles.removeFromLibrary(track: track)
                }
                loadCurrentPage(reset: true)
                refreshPlaylists()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func runFileOperationWithAuthorizationRetry(
        for track: Track,
        operation: @escaping (SecurityScopedRoot?) async throws -> Void
    ) async throws {
        do {
            try await operation(nil)
        } catch {
            guard Self.isPermissionFailure(error), let authorizedRoot = authorizeRootForWriting(track: track) else { throw error }
            do {
                try await operation(authorizedRoot)
            } catch {
                guard Self.isPermissionFailure(error) else { throw error }
                throw MassiveMusicError.metadataWriteFailed(text(
                    "選択した音楽フォルダへの書き込み権限を取得できませんでした。元の音楽ルートを選択し、SSDが読み書き可能か確認してください。元ファイルは変更していません。",
                    "Write permission to the selected music folder was not granted. Choose the original music root and confirm that the SSD is writable. The source file was not changed."
                ))
            }
        }
    }

    private static func isPermissionFailure(_ error: Error) -> Bool {
        func matches(_ value: NSError, visited: inout Set<ObjectIdentifier>) -> Bool {
            let identity = ObjectIdentifier(value)
            guard visited.insert(identity).inserted else { return false }
            if value.domain == NSCocoaErrorDomain,
               [CocoaError.fileReadNoPermission.rawValue, CocoaError.fileWriteNoPermission.rawValue].contains(value.code) {
                return true
            }
            if value.domain == NSPOSIXErrorDomain,
               [Int(EPERM), Int(EACCES)].contains(value.code) {
                return true
            }
            if let underlying = value.userInfo[NSUnderlyingErrorKey] as? NSError,
               matches(underlying, visited: &visited) {
                return true
            }
            if let detailed = value.userInfo[NSDetailedErrorsKey] as? [NSError] {
                return detailed.contains { matches($0, visited: &visited) }
            }
            return false
        }
        var visited: Set<ObjectIdentifier> = []
        return matches(error as NSError, visited: &visited)
    }

    private func authorizeRootForWriting(track: Track) -> SecurityScopedRoot? {
        guard let root = try? database.scanRoot(id: track.rootID) else { return nil }
        let panel = NSOpenPanel()
        panel.title = text("曲の編集・削除を許可", "Allow Song Editing and Deletion")
        panel.message = text(
            "「\(root.displayName)」フォルダをもう一度選択してください。曲ファイルを書き換える権限を安全に保存します。",
            "Choose the “\(root.displayName)” folder again to securely save permission to modify song files."
        )
        panel.directoryURL = URL(filePath: root.lastKnownPath).deletingLastPathComponent()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let selected = panel.url else { return nil }
        let candidate = selected.appending(path: track.relativePath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            errorMessage = text("元の音楽フォルダを選択してください。", "Choose the original music folder.")
            return nil
        }
        do {
            let scoped = try SecurityScopedRoot.create(for: selected)
            try database.updateScanRootAuthorization(id: root.id, bookmark: scoped.bookmark, path: selected.path)
            return scoped
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func importNewTracks() {
        let panel = NSOpenPanel()
        panel.title = text("ローカル受信箱へ取り込む曲を選択", "Choose Songs for Local Inbox")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        var allowedTypes: [UTType] = [.mp3, .mpeg4Audio, .wav]
        if let flacType = UTType("org.xiph.flac") {
            allowedTypes.append(flacType)
        } else if let flacType = UTType(filenameExtension: "flac") {
            allowedTypes.append(flacType)
        }
        panel.allowedContentTypes = allowedTypes
        guard panel.runModal() == .OK else { return }
        
        importURLs(panel.urls)
    }

    func importURLs(_ urls: [URL], toPlaylist playlistID: Int64? = nil) {
        var fileURLs: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
                if isDir.boolValue {
                    if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: nil) {
                        while let fileURL = enumerator.nextObject() as? URL {
                            fileURLs.append(fileURL)
                        }
                    }
                } else {
                    fileURLs.append(url)
                }
            }
        }
        
        let allowedExtensions = ["mp3", "m4a", "wav", "flac"]
        let filteredURLs = fileURLs.filter { allowedExtensions.contains($0.pathExtension.lowercased()) }
        
        guard !filteredURLs.isEmpty else { return }
        
        let hasFlac = filteredURLs.contains { $0.pathExtension.lowercased() == "flac" }
        if hasFlac {
            let alert = NSAlert()
            alert.messageText = text("FLACファイルをMP3に変換しますか？", "Convert FLAC files to MP3?")
            alert.informativeText = text(
                "取り込むファイルにFLACが含まれています。MP3に変換して取り込みますか？\n「そのまま取り込む」を選択した場合は元のFLAC形式で追加します。",
                "The imported files contain FLAC. Would you like to convert them to MP3?\nSelecting 'Import As-Is' will add them in their original FLAC format."
            )
            alert.addButton(withTitle: text("MP3に変換する", "Convert to MP3"))
            alert.addButton(withTitle: text("そのまま取り込む", "Import As-Is"))
            alert.addButton(withTitle: text("キャンセル", "Cancel"))
            
            if let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first {
                alert.beginSheetModal(for: window) { response in
                    if response == .alertFirstButtonReturn {
                        self.performImport(urls: filteredURLs, convertFlac: true, playlistID: playlistID)
                    } else if response == .alertSecondButtonReturn {
                        self.performImport(urls: filteredURLs, convertFlac: false, playlistID: playlistID)
                    }
                }
            } else {
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    performImport(urls: filteredURLs, convertFlac: true, playlistID: playlistID)
                } else if response == .alertSecondButtonReturn {
                    performImport(urls: filteredURLs, convertFlac: false, playlistID: playlistID)
                }
            }
        } else {
            performImport(urls: filteredURLs, convertFlac: false, playlistID: playlistID)
        }
    }

    private func performImport(urls: [URL], convertFlac: Bool, playlistID: Int64?) {
        Task { [weak self] in
            guard let self else { return }
            defer { importProgress = .idle }
            do {
                let primary = storageDestinations.first(where: \.isPrimary)
                guard let primaryDest = primary else {
                    throw MassiveMusicError.metadataWriteFailed(
                        text("保管先が設定されていません。画面右上の「保管先設定」ボタンからメインの保管場所を選択してください。",
                             "No storage destination configured. Choose a primary storage using the settings button in the top right.")
                    )
                }
                
                // Ensure a scan root exists for the primary storage destination (with NFC path normalization)
                let targetPath = primaryDest.path.precomposedStringWithCanonicalMapping
                var primaryRootID: Int64 = 0
                if let root = try? database.scanRoots().first(where: { $0.lastKnownPath.precomposedStringWithCanonicalMapping == targetPath }) {
                    primaryRootID = root.id
                } else {
                    let rootID = try database.addScanRoot(
                        displayName: primaryDest.name,
                        bookmark: primaryDest.bookmark,
                        volumeUUID: nil,
                        path: targetPath
                    )
                    primaryRootID = rootID
                }
                
                if primaryRootID == 0 {
                    if let firstRoot = try? database.scanRoots().first {
                        primaryRootID = firstRoot.id
                    }
                }
                
                guard primaryRootID > 0 else {
                    throw MassiveMusicError.metadataWriteFailed(
                        text("有効なスキャンルートが見つかりませんでした。保管先設定を確認してください。",
                             "Could not find or create a valid scan root. Please check your storage settings.")
                    )
                }
                
                let primaryAvailable = primaryStorageIsConnected
                    && FileManager.default.fileExists(atPath: targetPath)
                var importedTrackIDs: [Int64] = []
                let recordImportedTrack: (Int64) throws -> Void = { trackID in
                    importedTrackIDs.append(trackID)
                    // Add each successful import immediately. Waiting for the
                    // whole FLAC batch meant a stalled or failed later file
                    // left the playlist empty even though earlier songs had
                    // already been converted and registered.
                    if let playlistID {
                        _ = try self.database.addTracks([trackID], toPlaylist: playlistID)
                    }
                }
                
                // 1. Separate URLs into in-place (already under primary storage) and staged (needs copy/convert/move)
                var inplaceURLs: [URL] = []
                var stageURLs: [URL] = []
                
                for url in urls {
                    let standardURL = url.standardizedFileURL
                    let isUnderPrimary = standardURL.path.precomposedStringWithCanonicalMapping.hasPrefix(targetPath)
                    let isFlac = standardURL.pathExtension.lowercased() == "flac"
                    
                    if isUnderPrimary && (!isFlac || !convertFlac) {
                        inplaceURLs.append(standardURL)
                    } else {
                        stageURLs.append(url)
                    }
                }
                
                let getRelativePath = { (fileURL: URL) -> String in
                    let filePath = fileURL.standardizedFileURL.path.precomposedStringWithCanonicalMapping
                    if filePath.hasPrefix(targetPath) {
                        let index = filePath.index(filePath.startIndex, offsetBy: targetPath.count)
                        var rel = String(filePath[index...])
                        if rel.hasPrefix("/") {
                            rel.removeFirst()
                        }
                        return rel
                    }
                    return fileURL.lastPathComponent
                }
                
                // Reusable track registration closure
                let processAndCommitTrack = { @MainActor (localURL: URL, relativePath: String, isPendingImportItem: PendingImport?) async throws -> Int64 in
                    var activeURL = localURL
                    var activeRelativePath = relativePath
                    var movedItem: URL?
                    
                    if let item = isPendingImportItem, primaryAvailable, let primaryDest = primary {
                        let targetURL = try await self.storage.move(item, to: primaryDest)
                        activeURL = targetURL
                        activeRelativePath = getRelativePath(targetURL)
                        movedItem = targetURL
                    }
                    
                    let metadata = await AudioMetadataReader.read(url: activeURL)
                    let format = activeURL.pathExtension.uppercased()
                    let fileSize = (try? activeURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
                    let resKeys: Set<URLResourceKey> = [.fileResourceIdentifierKey, .volumeUUIDStringKey]
                    let resValues = try? activeURL.resourceValues(forKeys: resKeys)
                    let volumeUUID = resValues?.volumeUUIDString ?? "unknown-volume"
                    let resourceID = resValues?.fileResourceIdentifier.map { String(describing: $0) }
                    let identityKey: String
                    if let resourceID, !resourceID.isEmpty {
                        identityKey = "\(volumeUUID)|resource|\(resourceID)"
                    } else {
                        identityKey = "\(volumeUUID)|path|\(activeRelativePath)"
                    }
                    
                    let track = Track(
                        id: 0,
                        rootID: primaryRootID,
                        relativePath: activeRelativePath,
                        filename: activeURL.lastPathComponent,
                        title: metadata.title,
                        artist: metadata.artist,
                        album: metadata.album,
                        albumArtist: metadata.albumArtist,
                        genre: metadata.genre,
                        discNumber: metadata.discNumber,
                        trackNumber: metadata.trackNumber,
                        duration: metadata.duration,
                        fileSize: fileSize,
                        modifiedAt: Date(),
                        format: format,
                        bitrate: metadata.bitrate,
                        hasArtwork: metadata.hasArtwork,
                        isAvailable: true,
                        addedAt: Date()
                    )
                    
                    let trackImport = TrackImport(identityKey: identityKey, fileResourceID: nil, track: track)
                    let sessionID = try self.database.createScanSession(rootID: primaryRootID)
                    _ = try self.database.commitScanBatch(imports: [trackImport], unchangedIdentityKeys: [], sessionID: sessionID)
                    try self.database.updateScanSession(id: sessionID, state: .completed, cursor: nil, discovered: 1, processed: 1, changed: 1, skipped: 0, errors: 0, finished: true)
                    
                    guard let trackID = try? self.database.trackID(forIdentityKey: identityKey) else {
                        throw MassiveMusicError.metadataWriteFailed("Failed to get track ID")
                    }
                    
                    // Cache copy (only if storage is external). When the main
                    // drive is absent this becomes the authoritative retained
                    // source until reconnect, so failures must not be ignored.
                    var retainedCacheURL: URL?
                    if self.isStorageExternal {
                        let cacheURL = OfflineCacheManager.cacheDirectoryURL().appending(path: "\(trackID).\(format.lowercased())")
                        if !FileManager.default.fileExists(atPath: cacheURL.path) {
                            try FileManager.default.copyItem(at: activeURL, to: cacheURL)
                        }
                        try self.database.recordCachedTrack(
                            trackID: trackID, path: cacheURL.path, fileSize: fileSize,
                            pinned: !primaryAvailable
                        )
                        retainedCacheURL = cacheURL
                        try? self.database.recordTrackActivity(
                            trackID: trackID, kind: .addedToCache, absolutePath: cacheURL.path
                        )
                    }
                    
                    if let item = isPendingImportItem {
                        if let targetURL = movedItem {
                            try? self.database.recordTrackActivity(
                                trackID: trackID, kind: .addedToMainStorage,
                                absolutePath: targetURL.path
                            )
                        } else {
                            if let cacheURL = retainedCacheURL {
                                try self.database.updatePendingImport(
                                    id: item.id, state: .keptLocal, localPath: cacheURL.path
                                )
                                if activeURL.standardizedFileURL != cacheURL.standardizedFileURL {
                                    try? FileManager.default.removeItem(at: activeURL)
                                }
                            } else {
                                try self.database.updatePendingImport(
                                    id: item.id, state: .keptLocal, localPath: activeURL.path
                                )
                            }
                        }
                    }
                    
                    return trackID
                }
                
                // 2. Register in-place URLs (already in destination, no copying/moving)
                for url in inplaceURLs {
                    let rel = getRelativePath(url)
                    if let trackID = try? await processAndCommitTrack(url, rel, nil) {
                        try recordImportedTrack(trackID)
                    }
                }
                
                // 3. Process staged URLs (external or needs FLAC conversion)
                if !stageURLs.isEmpty {
                    var failures: [String] = []
                    let totalStageFiles = stageURLs.count
                    for (index, sourceURL) in stageURLs.enumerated() {
                        let currentIndex = index + 1
                        let displayName = sourceURL.lastPathComponent
                        do {
                            let staged = try await storage.stage([sourceURL], convertFlac: convertFlac) { [weak self] _, _, fileProgress in
                                Task { @MainActor in
                                    self?.importProgress = ImportProgress(
                                        state: .converting,
                                        currentFileIndex: currentIndex,
                                        totalFiles: totalStageFiles,
                                        fileProgress: fileProgress,
                                        currentFileName: displayName
                                    )
                                }
                            }
                            guard let item = staged.first else { continue }
                            let localURL = URL(filePath: item.localPath)
                            await MainActor.run {
                                self.importProgress = ImportProgress(
                                    state: .moving,
                                    currentFileIndex: currentIndex,
                                    totalFiles: totalStageFiles,
                                    fileProgress: 1.0,
                                    currentFileName: displayName
                                )
                            }
                            let trackID = try await processAndCommitTrack(localURL, item.filename, item)
                            try recordImportedTrack(trackID)
                        } catch {
                            failures.append("\(displayName): \(error.localizedDescription)")
                        }
                    }
                    if !failures.isEmpty {
                        errorMessage = text(
                            "\(failures.count)曲を取り込めませんでした:\n\(failures.joined(separator: "\n"))",
                            "Could not import \(failures.count) song(s):\n\(failures.joined(separator: "\n"))"
                        )
                    }
                }
                
                if primaryAvailable, let primaryDest = primary {
                    startScan(url: URL(filePath: primaryDest.path))
                }
                
                if playlistID != nil, !importedTrackIDs.isEmpty {
                    refreshPlaylists()
                }
                
                refreshStorage()
                loadCurrentPage(reset: true)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func chooseStorageDestination() {
        let panel = NSOpenPanel()
        panel.title = text("今後の保存先を選択", "Choose Storage Destination")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do { applyStorageDestinations(try await storage.addDestination(url)) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func ensureDefaultStorageDestination() {
        do {
            try database.renameVibeStorageDestinationToMain()
            let destinations = try database.storageDestinations()
            if destinations.isEmpty {
                if let existingRoot = try database.scanRoots().first {
                    _ = try database.addStorageDestination(
                        name: "メイン保管先",
                        path: existingRoot.lastKnownPath,
                        bookmark: existingRoot.bookmark
                    )
                } else {
                    let fm = FileManager.default
                    guard let musicURL = fm.urls(for: .musicDirectory, in: .userDomainMask).first else {
                        applyStorageDestinations([])
                        return
                    }
                    let vibeURL = musicURL.appending(path: "Vibe", directoryHint: .isDirectory)
                    try fm.createDirectory(at: vibeURL, withIntermediateDirectories: true)
                    
                    let scoped = try SecurityScopedRoot.create(for: vibeURL)
                    _ = try database.addStorageDestination(name: "メイン保管先", path: vibeURL.path, bookmark: scoped.bookmark)
                    _ = try database.addScanRoot(displayName: "メイン保管先", bookmark: scoped.bookmark, volumeUUID: nil, path: vibeURL.path)
                }
            }
            applyStorageDestinations(try database.storageDestinations())
        } catch {
            print("Failed to initialize default storage destination: \(error)")
        }
    }

    func moveImport(_ item: PendingImport, to destination: StorageDestination) {
        Task {
            do {
                let targetURL = try await storage.move(item, to: destination)
                if let rootID = try database.scanRoots().first(where: {
                    URL(filePath: $0.lastKnownPath).standardizedFileURL.path ==
                        URL(filePath: destination.path).standardizedFileURL.path
                })?.id,
                   let trackID = try database.trackID(rootID: rootID, relativePath: item.filename) {
                    try database.recordTrackActivity(
                        trackID: trackID,
                        kind: .addedToMainStorage,
                        absolutePath: targetURL.path
                    )
                }
                refreshStorage()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func saveCacheSettings() {
        do {
            try database.setSetting(cacheEnabled ? "true" : "false", forKey: "cache.enabled")
            try database.setSetting(String(max(0, cacheTrackLimit)), forKey: "cache.trackLimit")
            Task {
                do {
                    try await offlineCache.enforceLimit()
                    if section == .cache { loadCurrentPage(reset: true) }
                } catch { errorMessage = error.localizedDescription }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func saveMusicBrainzSettings() {
        do {
            try database.setSetting(
                autoFillMusicBrainzTrackNumbers ? "true" : "false",
                forKey: "musicbrainz.autoFillTrackNumbers"
            )
            startBulkAutoFillIfNeeded()
        } catch { errorMessage = error.localizedDescription }
    }

    private func startBulkAutoFillIfNeeded() {
        guard autoFillMusicBrainzTrackNumbers else {
            bulkAutoFillTask?.cancel()
            bulkAutoFillTask = nil
            isBulkAutoFilling = false
            bulkAutoFillProgress = ""
            return
        }
        
        bulkAutoFillTask?.cancel()
        bulkAutoFillTask = Task {
            await runBulkAutoFill()
        }
    }

    private func runBulkAutoFill() async {
        await MainActor.run {
            isBulkAutoFilling = true
            bulkAutoFillProgress = text("一括オートフィル準備中...", "Preparing bulk auto-fill...")
        }
        
        defer {
            Task { @MainActor in
                isBulkAutoFilling = false
                bulkAutoFillProgress = ""
            }
        }
        
        let logPath = "/tmp/vibe_bulk_autofill.log"
        let logMessage = "=== Bulk Auto-Fill Started at \(Date()) ===\n"
        try? logMessage.write(toFile: logPath, atomically: true, encoding: .utf8)
        
        guard let tracks = try? database.allTracksMissingNumbers() else { return }
        guard !tracks.isEmpty else {
            try? "No tracks missing track/disc numbers found.\n".write(toFile: logPath, atomically: true, encoding: .utf8)
            return
        }
        
        // Group tracks by (artist, album)
        var groups: [String: [Track]] = [:]
        for track in tracks {
            let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            let album = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !artist.isEmpty, !album.isEmpty else { continue }
            let key = "\(artist.lowercased())|\(album.lowercased())"
            groups[key, default: []].append(track)
        }
        
        let totalAlbums = groups.count
        var processedAlbums = 0
        var updatedCount = 0
        
        let fileLogger = { (msg: String) in
            if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                fileHandle.seekToEndOfFile()
                if let data = msg.data(using: .utf8) {
                    fileHandle.write(data)
                }
                fileHandle.closeFile()
            }
            print(msg, terminator: "")
        }
        
        fileLogger("Found \(tracks.count) tracks missing numbers, grouped into \(totalAlbums) albums.\n")
        
        let normalized = { (val: String) -> String in
            val.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
                .filter { $0.isLetter || $0.isNumber }
        }
        
        for (artistAlbumKey, localTracks) in groups {
            guard !Task.isCancelled else { break }
            guard let firstTrack = localTracks.first else { continue }
            
            processedAlbums += 1
            let albumName = firstTrack.album
            let artistName = firstTrack.artist
            
            await MainActor.run {
                bulkAutoFillProgress = text(
                    "解析中 (\(processedAlbums)/\(totalAlbums)): \(artistName) - \(albumName)",
                    "Processing (\(processedAlbums)/\(totalAlbums)): \(artistName) - \(albumName)"
                )
            }
            
            do {
                // Fetch candidates
                let candidates = try await musicMetadata.candidates(for: firstTrack)
                let localCount = try self.database.albumTrackCount(album: albumName, artist: artistName)
                
                // Find matching release candidate
                guard let candidate = candidates.first(where: { cand in
                    normalized(cand.artist) == normalized(artistName) &&
                    normalized(cand.album) == normalized(albumName) &&
                    cand.mediumTrackCount == localCount
                }) else {
                    continue
                }
                
                fileLogger("Matching album found: \(artistName) - \(albumName) (ReleaseID: \(candidate.releaseID))\n")
                
                // Fetch full tracklist for this release
                let mbTracks = try await musicMetadata.lookupRelease(releaseID: candidate.releaseID)
                
                // Match local tracks with MusicBrainz tracks by title
                for localTrack in localTracks {
                    guard !Task.isCancelled else { break }
                    let localTitleNorm = normalized(localTrack.title)
                    if let matchedMBTrack = mbTracks.first(where: { normalized($0.title) == localTitleNorm }) {
                        // Apply numbers!
                        var edit = TrackMetadataEdit(track: localTrack)
                        edit.discNumber = matchedMBTrack.discNumber
                        edit.trackNumber = matchedMBTrack.trackNumber
                        
                        // Update
                        try await self.updateMetadataAsync(for: localTrack, edit: edit)
                        updatedCount += 1
                        
                        let updateLog = "  -> Updated: \(localTrack.title) -> Disc: \(matchedMBTrack.discNumber), Track: \(matchedMBTrack.trackNumber) (File: \(localTrack.filename))\n"
                        fileLogger(updateLog)
                    }
                }
            } catch {
                fileLogger("  Error processing \(artistName) - \(albumName): \(error.localizedDescription)\n")
            }
        }
        
        fileLogger("=== Bulk Auto-Fill Finished. Total updated: \(updatedCount) tracks ===\n")
        await MainActor.run {
            loadCurrentPage(reset: false)
        }
    }

    func saveMetadataNormalizationSettings() {
        do {
            try database.setSetting(
                normalizeMetadataCharacterWidths ? "true" : "false",
                forKey: "metadata.normalizeCharacterWidths"
            )
            if normalizeMetadataCharacterWidths {
                startWidthNormalization()
            } else {
                widthNormalizationTask?.cancel()
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func saveID3MigrationSettings() {
        do {
            try database.setSetting(
                autoMigrateID3v22ToV23 ? "true" : "false",
                forKey: "metadata.autoMigrateID3v22ToV23"
            )
            if autoMigrateID3v22ToV23 {
                startID3Migration()
            } else {
                id3MigrationTask?.cancel()
                id3MigrationTask = nil
                isID3Migrating = false
                id3MigrationProgress = ""
            }
        } catch { errorMessage = error.localizedDescription }
    }

    private func startID3Migration() {
        guard autoMigrateID3v22ToV23, id3MigrationTask == nil else { return }
        guard allScanRootsAreConnected() else { return }
        id3MigrationTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            await MainActor.run {
                self.isID3Migrating = true
                self.id3MigrationProgress = self.text("ID3v2.2移行のスキャン準備中...", "Preparing ID3v2.2 migration scan...")
            }
            defer {
                Task { @MainActor in
                    self.isID3Migrating = false
                    self.id3MigrationProgress = ""
                    self.id3MigrationTask = nil
                }
            }

            let logPath = "/tmp/vibe_id3_migration.log"
            let logMessage = "=== ID3v2.2 Migration Started at \(Date()) ===\n"
            try? logMessage.write(toFile: logPath, atomically: true, encoding: .utf8)

            let fileLogger = { (msg: String) in
                if let fileHandle = FileHandle(forWritingAtPath: logPath) {
                    fileHandle.seekToEndOfFile()
                    if let data = msg.data(using: .utf8) {
                        fileHandle.write(data)
                    }
                    fileHandle.closeFile()
                }
                print(msg, terminator: "")
            }

            var afterID: Int64 = 0
            var migratedCount = 0
            var scannedCount = 0
            var failedCount = 0

            do {
                while !Task.isCancelled, self.autoMigrateID3v22ToV23 {
                    let requestedAfterID = afterID
                    let page = try await Task.detached(priority: .utility) {
                        try self.database.mp3TracksForID3Migration(afterID: requestedAfterID, limit: 200)
                    }.value
                    guard !page.isEmpty else { break }

                    for track in page {
                        try Task.checkCancellation()
                        afterID = track.id
                        scannedCount += 1

                        if await self.trackFiles.isID3v22Tag(for: track) {
                            await MainActor.run {
                                self.id3MigrationProgress = self.text(
                                    "ID3v2.2タグをv2.3へ移行中 (\(migratedCount)曲変換済み): \(track.artist) - \(track.title)",
                                    "Migrating ID3v2.2 tag to v2.3 (\(migratedCount) converted): \(track.artist) - \(track.title)"
                                )
                            }

                            let edit = TrackMetadataEdit(track: track)
                            do {
                                try await self.trackFiles.updateMetadata(
                                    track: track, edit: edit, repairingCorruptID3: true
                                )
                                migratedCount += 1
                                fileLogger("  -> Migrated ID3v2.2 to ID3v2.3: \(track.artist) - \(track.title) (\(track.filename))\n")
                            } catch {
                                failedCount += 1
                                fileLogger("  Error migrating \(track.filename): \(error.localizedDescription)\n")
                            }
                        }
                    }
                }

                fileLogger("=== ID3v2.2 Migration Finished. Scanned: \(scannedCount), Migrated: \(migratedCount), Failed: \(failedCount) ===\n")
                await MainActor.run {
                    self.loadCurrentPage(reset: false)
                }
            } catch is CancellationError {
                // Task cancelled
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func enrich(_ track: Track?) {
        enrichmentTask?.cancel()
        enrichedInfo = nil
        similarTracks = []
        genreSuggestion = nil
        enrichedTrackID = track?.id
        guard let track else { return }
        autoClassifyGenreIfNeeded(for: track)
        isEnriching = true
        enrichmentTask = Task { [weak self] in
            guard let self else { return }
            let currentTrack = (try? database.track(id: track.id)) ?? track
            async let info = enrichment.info(for: currentTrack, languageCode: language.rawValue)
            async let similar = Task.detached { try self.database.similarTracks(to: currentTrack) }.value
            let resolvedInfo = await info
            let resolvedSimilar = (try? await similar) ?? []
            guard !Task.isCancelled else { return }
            enrichedInfo = resolvedInfo
            similarTracks = resolvedSimilar
            isEnriching = false
        }
    }

    /// Automatically fills a missing genre when playback starts. The built-in
    /// classifier is deterministic and local, so normal playback never opens
    /// Keychain dialogs or incurs API charges. Users can still request a richer
    /// OpenAI/Gemini suggestion from the information panel.
    func autoClassifyGenreIfNeeded(for track: Track) {
        let currentGenre = track.genre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard currentGenre.isEmpty || currentGenre == "未判定" || currentGenre == "Unknown" else { return }
        guard automaticallyClassifiedTrackIDs.insert(track.id).inserted else { return }
        let suggestion = localSuggestion(for: track)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.detached {
                    try self.database.updateTrackGenre(id: track.id, genre: suggestion.genre)
                }.value
                if section != .upNext { loadCurrentPage(reset: false) }
            } catch {
                automaticallyClassifiedTrackIDs.remove(track.id)
                errorMessage = error.localizedDescription
            }
        }
    }

    private func refreshEnrichmentIfNeeded(updatedTrackIDs: Set<Int64>) {
        guard let enrichedTrackID, updatedTrackIDs.contains(enrichedTrackID) else { return }
        enrich((try? database.track(id: enrichedTrackID)) ?? nil)
    }

    func createPlaylist() {
        Task {
            do {
                let index = playlists.count + 1
                let name = text("新規プレイリスト \(index)", "New Playlist \(index)")
                _ = try await Task.detached { try self.database.createPlaylist(name: name) }.value
                refreshPlaylists()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func deletePlaylist(id: Int64) {
        Task {
            do {
                try await Task.detached { try self.database.deletePlaylist(id: id) }.value
                if selectedPlaylistID == id {
                    selectedPlaylistID = nil
                    changeSection(.tracks)
                }
                refreshPlaylists()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func deleteSelectedPlaylist() {
        guard let id = selectedPlaylistID else { return }
        Task {
            do {
                try await Task.detached { try self.database.deletePlaylist(id: id) }.value
                selectedPlaylistID = nil
                refreshPlaylists()
                changeSection(.tracks)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func renameSelectedPlaylist() {
        guard let id = selectedPlaylistID,
              let playlist = playlists.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = text("プレイリスト名を変更", "Rename Playlist")
        alert.addButton(withTitle: text("変更", "Rename"))
        alert.addButton(withTitle: text("キャンセル", "Cancel"))
        let field = NSTextField(string: playlist.name)
        field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = text("プレイリスト名を入力してください。", "Enter a playlist name.")
            return
        }
        Task {
            do {
                try await Task.detached { try self.database.renamePlaylist(id: id, name: name) }.value
                refreshPlaylists()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func addSelectionToPlaylist(_ playlistID: Int64) {
        addTrackIDsToPlaylist(Array(selectedTrackIDs), playlistID: playlistID)
    }

    func addTrackIDsToPlaylist(_ ids: [Int64], playlistID: Int64) {
        guard !ids.isEmpty else { return }
        Task {
            do {
                _ = try await Task.detached {
                    try self.database.addTracks(ids, toPlaylist: playlistID)
                }.value
                refreshPlaylists()
                if selectedPlaylistID == playlistID {
                    loadCurrentPage(reset: false)
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func removeSelectionFromPlaylist() {
        guard let playlistID = selectedPlaylistID else { return }
        let ids = selectedTrackIDs
        Task {
            do {
                try await Task.detached {
                    for id in ids { try self.database.removeTrack(id, fromPlaylist: playlistID) }
                }.value
                loadCurrentPage(reset: false)
                refreshPlaylists()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func moveTrackInSelectedPlaylist(_ trackID: Int64, by delta: Int) {
        guard let playlistID = selectedPlaylistID,
              let localIndex = tracks.firstIndex(where: { $0.id == trackID }) else { return }
        let from = offset + localIndex
        let to = min(max(0, from + delta), max(0, totalCount - 1))
        guard from != to else { return }
        Task {
            do {
                try await Task.detached {
                    try self.database.movePlaylistItem(playlistID: playlistID, from: from, to: to)
                }.value
                loadCurrentPage(reset: false)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func importPlaylist() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.m3uPlaylist]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let playlistID = try database.createPlaylist(name: url.deletingPathExtension().lastPathComponent)
                _ = try await PlaylistTransfer.importM3U(source: url, playlistID: playlistID, database: database)
                refreshPlaylists()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func exportSelectedPlaylist() {
        guard let playlistID = selectedPlaylistID else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.m3uPlaylist]
        panel.nameFieldStringValue = "playlist.m3u8"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await Task.detached {
                    try PlaylistTransfer.exportM3U8(
                        playlistID: playlistID, database: self.database, destination: url
                    )
                }.value
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func apply(page: TrackPage) {
        tracks = page.tracks
        activityEvents = []
        facets = []
        albumSummaries = []
        artistSummaries = []
        variationCandidates = []
        offset = page.offset
        totalCount = page.totalCount
        selectedTrackIDs.formIntersection(page.tracks.map(\.id))
    }

    private func apply(albumPage: AlbumSummaryPage) {
        albumSummaries = albumPage.albums
        let visibleAlbumIDs = Set(albumPage.albums.map(\.id))
        for id in Array(albumArtworkURLs.keys) where !visibleAlbumIDs.contains(id) {
            albumArtworkURLs.removeValue(forKey: id)
        }
        loadingAlbumArtworkIDs.formIntersection(visibleAlbumIDs)
        activityEvents = []
        artistSummaries = []
        tracks = []
        facets = []
        offset = albumPage.offset
        totalCount = albumPage.totalCount
    }

    private func apply(artistPage: ArtistSummaryPage) {
        artistSummaries = artistPage.artists
        let visibleArtistNames = Set(artistPage.artists.map(\.name))
        for name in Array(artistImageURLs.keys) where !visibleArtistNames.contains(name) {
            artistImageURLs.removeValue(forKey: name)
        }
        loadingArtistImageNames.formIntersection(visibleArtistNames)
        activityEvents = []
        albumSummaries = []
        tracks = []
        facets = []
        offset = artistPage.offset
        totalCount = artistPage.totalCount
    }

    private var visibleItemCount: Int {
        if section == .activityLog { return activityEvents.count }
        if section == .diagnostics, diagnosticKind == .suspectedVariations { return variationCandidates.count }
        if selectedGenre != nil {
            switch genreDetailMode {
            case .albums: return albumSummaries.count
            case .artists: return artistSummaries.count
            case .tracks: return tracks.count
            }
        }
        if selectedAlbum != nil || !tracks.isEmpty { return tracks.count }
        if selectedArtist?.name.isEmpty == true { return tracks.count }
        if selectedArtist != nil || section == .albums { return albumSummaries.count }
        if section == .artists { return artistSummaries.count }
        return facets.count
    }

    private var alphabetIndexTarget: LibraryIndexTarget? {
        if selectedAlbum != nil || selectedArtist?.name.isEmpty == true { return .tracks }
        if selectedArtist != nil { return .albums }
        if selectedGenre != nil {
            switch genreDetailMode {
            case .albums: return .albums
            case .artists: return .artists
            case .tracks: return .tracks
            }
        }
        switch section {
        case .tracks: return .tracks
        case .recentlyAdded: return .tracks
        case .albums: return .albums
        case .artists: return .artists
        default: return nil
        }
    }

    private var usesKeysetPaging: Bool {
        selectedAlbum == nil && selectedArtist == nil && selectedGenre == nil
            && (section == .tracks || section == .recentlyAdded)
    }

    private func refreshMetadataDiagnostics() {
        metadataSummaryTask?.cancel()
        metadataSummaryTask = Task { [weak self] in
            guard let self else { return }
            do {
                var summaries = try await Task.detached { try self.database.metadataIssueSummaries() }.value
                try Task.checkCancellation()
                let variationCount = try await Task.detached { try self.database.metadataVariationCount() }.value
                try Task.checkCancellation()
                summaries.append(MetadataIssueSummary(kind: .suspectedVariations, count: variationCount))
                diagnosticSummaries = summaries
            } catch is CancellationError {
                return
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func updateDiagnosticSummary(kind: MetadataIssueKind, count: Int) {
        if let index = diagnosticSummaries.firstIndex(where: { $0.kind == kind }) {
            diagnosticSummaries[index] = MetadataIssueSummary(kind: kind, count: count)
        } else {
            diagnosticSummaries.append(MetadataIssueSummary(kind: kind, count: count))
        }
    }

    private func refreshPlaylists() {
        Task {
            do {
                playlists = try await Task.detached { try self.database.playlists() }.value
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func refreshStorage() {
        Task {
            do {
                pendingImports = try await Task.detached { try self.database.pendingImports() }.value
                applyStorageDestinations(
                    try await Task.detached { try self.database.storageDestinations() }.value
                )
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func applyStorageDestinations(_ destinations: [StorageDestination]) {
        storageDestinations = destinations
        if let primary = destinations.first(where: \.isPrimary) {
            primaryStorageIsConnected = FileManager.default.fileExists(atPath: primary.path)
        } else {
            primaryStorageIsConnected = false
        }
        if !isStorageExternal, section == .cache {
            changeSection(.tracks)
        }
    }

    private func refreshDifferenceSummary() {
        Task { unavailableTrackCount = (try? await Task.detached { try self.database.unavailableTrackCount() }.value) ?? 0 }
    }

    private func refreshSidebarCounts() {
        Task {
            let counts = await Task.detached {
                (
                    (try? self.database.favoriteTrackCount()) ?? 0,
                    (try? self.database.recentlyAddedTrackCount()) ?? 0
                )
            }.value
            favoriteTrackCount = counts.0
            recentlyAddedTrackCount = counts.1
        }
    }

    private func monitorDrives() async {
        var hadMissingRoots = false
        while !Task.isCancelled {
            do {
                let roots = try await Task.detached { try self.database.scanRoots() }.value
                var missingNames: [String] = []
                var missingRootIDs: Set<Int64> = []
                for root in roots {
                    let available: Bool
                    if let scoped = try? SecurityScopedRoot.resolve(bookmark: root.bookmark) {
                        available = FileManager.default.fileExists(atPath: scoped.url.path)
                    } else {
                        available = false
                    }
                    try? await Task.detached {
                        try self.database.setRootAvailability(id: root.id, isAvailable: available)
                    }.value
                    if !available {
                        missingNames.append(root.displayName)
                        missingRootIDs.insert(root.id)
                    }
                }
                unavailableRootIDs = missingRootIDs
                if let primary = storageDestinations.first(where: \.isPrimary) {
                    primaryStorageIsConnected = FileManager.default.fileExists(atPath: primary.path)
                } else {
                    primaryStorageIsConnected = false
                }
                let hasMissingRoots = !missingNames.isEmpty
                driveMessage = hasMissingRoots ? "\(text("ドライブが接続されていません", "Drive is not connected")): \(missingNames.joined(separator: ", "))" : nil
                if primaryStorageIsConnected {
                    syncOfflineImportsIfNeeded()
                    syncPendingMetadataEditsIfNeeded()
                }
                if hadMissingRoots, !hasMissingRoots {
                    startLeadingTitleSpaceCleanup()
                }
                hadMissingRoots = hasMissingRoots
            } catch {
                driveMessage = error.localizedDescription
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }

    private func syncOfflineImportsIfNeeded() {
        guard let primary = storageDestinations.first(where: \.isPrimary), primaryStorageIsConnected else { return }
        guard !isSyncingOffline else { return }
        isSyncingOffline = true
        Task {
            defer { isSyncingOffline = false }
            do {
                let pending = try await Task.detached { try self.database.pendingImports() }.value
                let keptLocalItems = pending.filter { $0.state == .keptLocal }
                guard !keptLocalItems.isEmpty else { return }
                
                let primaryRootID: Int64
                if let root = try? database.scanRoots().first(where: { $0.lastKnownPath == primary.path }) {
                    primaryRootID = root.id
                } else {
                    primaryRootID = 1
                }
                
                for item in keptLocalItems {
                    let targetURL = try await storage.copyKeptLocalImport(item, to: primary)
                    if let trackID = try database.trackID(rootID: primaryRootID, relativePath: item.filename) {
                        try database.recordTrackActivity(
                            trackID: trackID,
                            kind: .addedToMainStorage,
                            absolutePath: targetURL.path
                        )
                        try database.setCachedTrackPinned(trackID: trackID, pinned: false)
                    }
                }
                
                startScan(url: URL(filePath: primary.path))
                refreshStorage()
            } catch {
                print("Failed to sync offline imports: \(error)")
            }
        }
    }

    private func syncPendingMetadataEditsIfNeeded() {
        guard primaryStorageIsConnected, !isSyncingPendingMetadata else { return }
        isSyncingPendingMetadata = true
        Task {
            defer { isSyncingPendingMetadata = false }
            do {
                let pending = try await Task.detached { try self.database.pendingMetadataEdits(limit: 50) }.value
                guard !pending.isEmpty else { return }
                for item in pending {
                    let track = try await Task.detached {
                        try self.database.track(id: item.trackID)
                    }.value
                    guard let track else {
                        try await Task.detached { try self.database.removePendingMetadataEdit(id: item.id) }.value
                        continue
                    }
                    let sourceFileIsAvailable = await trackFiles.sourceFileIsAvailable(for: track)
                    guard sourceFileIsAvailable else { continue }
                    try await runFileOperationWithAuthorizationRetry(for: track) {
                        try await self.trackFiles.updateMetadata(track: track, edit: item.edit, authorizedRoot: $0)
                    }
                    try await Task.detached { try self.database.removePendingMetadataEdit(id: item.id) }.value
                }
                loadCurrentPage(reset: false)
            } catch {
                print("Failed to sync pending metadata edits: \(error)")
            }
        }
    }
}
