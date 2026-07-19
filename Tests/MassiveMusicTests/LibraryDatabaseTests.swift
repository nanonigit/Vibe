import Foundation
import Testing
@testable import MassiveMusicCore

@Suite(.serialized)
struct LibraryDatabaseTests {
    @Test func storageTopologyOnlyUsesASeparateCacheForExternalMainStorage() {
        #expect(!StorageTopology.usesSeparateLocalCache(primaryPath: nil))
        #expect(!StorageTopology.usesSeparateLocalCache(primaryPath: "/Users/naoki/Music/Vibe"))
        #expect(!StorageTopology.usesSeparateLocalCache(primaryPath: "/"))
        #expect(StorageTopology.usesSeparateLocalCache(primaryPath: "/Volumes/Transcend/Music/Music"))
        #expect(StorageTopology.usesSeparateLocalCache(primaryPath: "/Volumes/External HDD"))
    }

    @Test func recentlyAddedLibraryIsPagedNewestFirst() throws {
        let context = try TestContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        let rootID = try context.database.addScanRoot(
            displayName: "Test", bookmark: Data(), volumeUUID: nil, path: context.directory.path
        )
        let sessionID = try context.database.createScanSession(rootID: rootID)
        let imports = [
            context.importedTrack(identity: "old", title: "Old", filename: "old.mp3", rootID: rootID, addedAt: Date(timeIntervalSince1970: 100)),
            context.importedTrack(identity: "new", title: "New", filename: "new.mp3", rootID: rootID, addedAt: Date(timeIntervalSince1970: 300)),
            context.importedTrack(identity: "middle", title: "Middle", filename: "middle.mp3", rootID: rootID, addedAt: Date(timeIntervalSince1970: 200))
        ]
        _ = try context.database.commitScanBatch(imports: imports, unchangedIdentityKeys: [], sessionID: sessionID)

        let first = try context.database.pageTracksAfter(
            sort: .dateAdded, direction: .descending, after: nil, limit: 2
        )
        let second = try context.database.pageTracksAfter(
            sort: .dateAdded, direction: .descending, after: first.tracks.last,
            logicalOffset: 2, limit: 2, knownTotal: first.totalCount
        )

        #expect(first.totalCount == 3)
        #expect(first.tracks.map(\.title) == ["New", "Middle"])
        #expect(second.tracks.map(\.title) == ["Old"])
        #expect(second.offset == 2)
    }

    @Test func recentLibraryAndStorageConnectionStateAreExplicitInTheUI() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let view = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(model.contains("case .recentlyAdded: text(\"最近追加した曲\", \"Recently Added\")"))
        #expect(model.contains("requestedSection == .recentlyAdded"))
        #expect(model.contains("primaryStorageIsConnected"))
        #expect(view.contains("接続中"))
        #expect(view.contains("未接続"))
        #expect(view.contains("Color.green"))
        #expect(view.contains("Color.orange"))
    }

    @Test func disconnectedImportsUseTheCacheAndReconnectCopiesWithoutRemovingIt() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let services = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryServices.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(services.contains("func copyKeptLocalImport"))
        #expect(services.contains("fileManager.copyItem(at: source, to: target)"))
        #expect(model.contains("state: .keptLocal, localPath: cacheURL.path"))
        #expect(model.contains("storage.copyKeptLocalImport(item, to: primary)"))
    }

    @Test func existingContainerLibraryWinsOverANewEmptyUnsandboxedDatabase() {
        let current = URL(filePath: "/Users/test/Library/Application Support/MassiveMusic/MassiveMusic.sqlite")
        let container = URL(filePath: "/Users/test/Library/Containers/com.local.MassiveMusic/Data/Library/Application Support/MassiveMusic/MassiveMusic.sqlite")

        #expect(LibraryDatabase.preferredApplicationSupportDatabase(
            defaultURL: current, containerURL: container, containerDatabaseExists: true
        ) == container)
        #expect(LibraryDatabase.preferredApplicationSupportDatabase(
            defaultURL: current, containerURL: container, containerDatabaseExists: false
        ) == current)
    }

    @Test func existingScanRootBecomesPrimaryStorageBeforeCreatingALocalDefault() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(source.contains("if let existingRoot = try database.scanRoots().first"))
        #expect(source.contains("path: existingRoot.lastKnownPath"))
        #expect(source.contains("bookmark: existingRoot.bookmark"))
    }

    @Test func automaticMetadataCleanupWaitsForEverySourceDrive() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(source.contains("private func allScanRootsAreConnected() -> Bool"))
        #expect(source.contains("guard allScanRootsAreConnected() else { return }"))
    }

    @Test func librarySidebarStaysExpandedAndOnlyShowsCacheForSeparateStorage() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(source.contains("Section(isExpanded: .constant(true))"))
        #expect(source.contains("ForEach(model.visibleLibrarySections)"))
    }

    @Test func librarySidebarCanBeDragReorderedAndPersistsItsOrder() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(content.contains(".draggable(section.rawValue)"))
        #expect(content.contains(".dropDestination(for: String.self)"))
        #expect(content.contains("model.moveLibrarySection(source, before: section)"))
        #expect(content.contains("model.moveLibrarySection(section, by: -1)"))
        #expect(content.contains("model.moveLibrarySection(section, by: 1)"))
        #expect(content.contains("model.text(\"並び替え\", \"Reorder\")"))
        #expect(model.contains("sidebar.libraryOrder"))
        #expect(model.contains("librarySectionOrder = order"))
    }

    @Test func storageAndDifferenceSidebarItemsOpenDistinctSettingsTabs() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(source.contains("model.text(\"保管先と取り込み\", \"Storage & Imports\")"))
        #expect(source.contains("settingsTab = .storage"))
        #expect(source.contains("settingsTab = .differences"))
        #expect(source.contains(".tag(SettingsTab.differences)"))
    }

    @Test func metadataWidthNormalizationChangesOnlyRequestedWidthVariants() {
        #expect(
            MetadataTextNormalizer.normalizedWidths("ﾗｳﾞ ｶﾞｯﾂ ＡＢＣ１２３！")
                == "ラヴ ガッツ ABC123!"
        )
        #expect(MetadataTextNormalizer.normalizedWidths("s a y ｍｙ name") == "s a y my name")
        #expect(MetadataTextNormalizer.normalizedWidths("Roman Ⅳ ① café") == "Roman Ⅳ ① café")
    }

    @Test func metadataWidthNormalizationIsOptionalAndResumable() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(content.contains("文字幅を自動で正規化"))
        #expect(content.contains("model.saveMetadataNormalizationSettings()"))
        #expect(model.contains("metadata.normalizeCharacterWidths"))
        #expect(model.contains("metadata.widthNormalizationCursor"))
        #expect(model.contains("tracksForWidthNormalization(afterID:"))
    }

    @Test func sidebarNavigationRowsUseFullWidthRectangularHitTargets() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(source.contains("private struct SidebarNavigationLabel: View"))
        #expect(source.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        #expect(source.contains(".contentShape(Rectangle())"))
        #expect(source.components(separatedBy: "SidebarNavigationLabel(").count - 1 >= 5)
    }

    @Test func bottomPlayerSharesArtworkAndReservesDedicatedLayoutSpace() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let bodyStart = try #require(source.range(of: "    var body: some View {"))
        let toolbarStart = try #require(source.range(of: "        .toolbar { toolbar }", range: bodyStart.upperBound..<source.endIndex))
        let rootLayout = String(source[bodyStart.lowerBound..<toolbarStart.lowerBound])

        #expect(source.contains("private struct PlayerArtwork: View"))
        #expect(source.components(separatedBy: "PlayerArtwork(").count - 1 >= 2)
        #expect(rootLayout.contains("VStack(spacing: 0)"))
        #expect(rootLayout.contains("NavigationSplitView"))
        #expect(rootLayout.contains("PlayerBar(player: player, model: model)"))
        #expect(rootLayout.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(!rootLayout.contains(".safeAreaInset(edge: .bottom"))
    }

    @Test func miniPlayerUsesCurrentTrackArtworkAndRefreshesItWhenTheTrackChanges() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let miniPlayerStart = try #require(source.range(of: "struct MiniPlayerView: View"))
        let miniPlayerSource = String(source[miniPlayerStart.lowerBound...])

        #expect(miniPlayerSource.contains("PlayerArtwork("))
        #expect(miniPlayerSource.contains("artworkURL: model.enrichedInfo?.artworkURL"))
        #expect(miniPlayerSource.contains(".onChange(of: player.currentTrack)"))
        #expect(miniPlayerSource.contains("model.enrich(track)"))
        #expect(!miniPlayerSource.contains("NSApplication.shared.applicationIconImage"))
    }

    @Test func miniPlayerDisablesNativeWindowResizingUntilExpanded() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/MassiveMusicApp.swift"))

        #expect(source.contains("window.styleMask.remove(.resizable)"))
        #expect(source.contains("window.styleMask.insert(.resizable)"))
        #expect(source.contains("window.standardWindowButton(.zoomButton)?.isEnabled = false"))
        #expect(source.contains("window.standardWindowButton(.zoomButton)?.isEnabled = true"))
    }

    @Test func trackContextMenuShowsPlaylistChoicesWithoutANestedSubmenu() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let menuStart = try #require(source.range(of: "    private func trackContextMenu"))
        let menuEnd = try #require(source.range(
            of: "\n    @ViewBuilder private var albumSummaryList",
            range: menuStart.upperBound..<source.endIndex
        ))
        let menu = String(source[menuStart.lowerBound..<menuEnd.lowerBound])

        #expect(menu.contains("Section(model.text(\"プレイリストに追加\", \"Add to Playlist\"))"))
        #expect(menu.contains("ForEach(model.playlists)"))
        #expect(menu.contains("model.createPlaylist()"))
        #expect(!menu.contains("Menu(model.text(\"プレイリストに追加\", \"Add to Playlist\"))"))
    }

    @Test func playlistsAreAvailableBeforeTheFirstContextMenuOpens() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(source.contains("playlists = (try? database.playlists()) ?? []"))
    }

    @Test func cachedLibraryKeepsControlsAndTrackTableInsideItsVisibleBounds() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(source.contains("private var cacheHeaderControls: some View"))
        #expect(source.contains("private var nonCacheHeaderControls: some View"))
        #expect(source.contains("private var headerControls: some View {\n        ViewThatFits(in: .horizontal)"))
        #expect(source.contains(".id(trackTableContextID)"))
        #expect(source.contains("private var trackTableContextID: String"))
    }

    @Test func appStartupNeverReadsKeychainOrPresentsAuthenticationUI() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let keychainSource = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/OpenAIGenreClassifier.swift"))
        let modelSource = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let initializerStart = try #require(modelSource.range(of: "    init(database:"))
        let initializerEnd = try #require(modelSource.range(of: "\n    var canGoPrevious:", range: initializerStart.upperBound..<modelSource.endIndex))
        let initializer = String(modelSource[initializerStart.lowerBound..<initializerEnd.lowerBound])

        #expect(keychainSource.contains("kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail"))
        #expect(keychainSource.contains("func readResult(allowAuthenticationUI: Bool)"))
        #expect(initializer.contains("restoreAIProviderConfigurationWithoutReadingKeys()"))
        #expect(!initializer.contains("refreshAIProviderStates"))
        #expect(modelSource.contains("try database.setSetting(\"true\", forKey: \"openai.keyConfigured\")"))
        #expect(modelSource.contains("try database.setSetting(\"true\", forKey: \"gemini.keyConfigured\")"))
        #expect(modelSource.contains("refreshAIProviderStates(allowAuthenticationUI: true, validateRemotely: true)"))
    }

    @Test func localAdHocBuildCanLoadItsEmbeddedCoreFramework() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let entitlements = try String(contentsOf: repository.appending(path: "Config/MassiveMusic.entitlements"))

        #expect(entitlements.contains("com.apple.security.cs.disable-library-validation"))
        #expect(entitlements.contains("<true/>"))
    }

    @Test func openingSettingsDoesNotImplicitlyAuthenticateAIProviders() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let settingsStart = try #require(source.range(of: "private struct LibrarySettingsView: View"))
        let settingsEnd = try #require(source.range(of: "\nprivate struct HoverTrackingView", range: settingsStart.upperBound..<source.endIndex))
        let settings = String(source[settingsStart.lowerBound..<settingsEnd.lowerBound])
        let appearStart = try #require(settings.range(of: "        .onAppear {"))
        let appearEnd = try #require(settings.range(of: "\n        }", range: appearStart.upperBound..<settings.endIndex))
        let onAppear = String(settings[appearStart.lowerBound..<appearEnd.upperBound])

        #expect(!onAppear.contains("validateAIProviders"))
        #expect(settings.contains("Button(model.text(\"接続を再確認\", \"Test Connections\"), action: model.validateAIProviders)"))
    }

    @Test func songsDefaultToTitleAscendingAndEverySettingsTabUsesTopAlignedLayout() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let settingsStart = try #require(content.range(of: "private struct LibrarySettingsView: View"))
        let settingsEnd = try #require(content.range(of: "\nprivate struct SettingsPage", range: settingsStart.upperBound..<content.endIndex))
        let settings = String(content[settingsStart.lowerBound..<settingsEnd.lowerBound])

        #expect(model.contains("@Published var sort: TrackSort = .title"))
        #expect(model.contains("if newSection == .tracks, exactFilter == nil {\n            sort = .title\n            sortDirection = .ascending\n        }"))
        #expect(!settings.contains("            Form {"))
        #expect(settings.components(separatedBy: "            SettingsPage {").count - 1 >= 5)
    }

    @Test func selectedTracksCanBeDraggedOntoAPlaylist() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(content.contains(".draggable(trackDragPayload(for: track))"))
        #expect(content.contains("let trackIDs = values.flatMap(parseTrackDragPayload)"))
        #expect(content.contains("model.addTrackIDsToPlaylist(trackIDs, playlistID: playlist.id)"))
        #expect(model.contains("func addTrackIDsToPlaylist(_ ids: [Int64], playlistID: Int64)"))
    }

    @Test func trackArtistAndAlbumNavigationUseTheEntireCellAsHitTarget() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(source.contains("private struct TrackNavigationCell: View"))
        #expect(source.contains(".frame(width: width, height: 32, alignment: .leading)"))
        #expect(source.contains(".contentShape(Rectangle())"))
        #expect(source.components(separatedBy: "TrackNavigationCell(").count - 1 >= 2)
    }

    @Test func doubleClickStartsAStreamingSequenceFromTheVisibleTrackList() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let playback = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/PlaybackController.swift"))

        #expect(content.contains("player.playFromList(track, context: context)"))
        #expect(playback.contains("func playFromList(_ track: Track, context: TrackPlaybackContext)"))
        #expect(playback.contains("database.adjacentTrack(in: context, from: cursor, direction: direction)"))
    }

    @Test func backFromArtistOrRenamedAlbumRestoresThePreviousIndexAndPage() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let closeStart = try #require(model.range(of: "    func closeDetail()"))
        let closeEnd = try #require(model.range(of: "\n    func genreDetailTitle", range: closeStart.upperBound..<model.endIndex))
        let closeDetail = String(model[closeStart.lowerBound..<closeEnd.lowerBound])

        #expect(model.contains("private struct BrowseReturnState"))
        #expect(model.contains("private var browseReturnStack: [BrowseReturnState]"))
        #expect(model.contains("selectedIndexToken: selectedIndexToken"))
        #expect(closeDetail.contains("restoreBrowseReturnState"))
        #expect(closeDetail.contains("loadCurrentPage(reset: false)"))
        #expect(model.contains("if let selectedAlbum, selectedAlbum.id != editedAlbumIdentity"))
        #expect(model.contains("closeDetail()"))
        #expect(content.contains("model.selectedIndexToken = token"))
        #expect(!content.contains("@State private var selectedIndexToken"))
    }

    @Test func musicBrainzCandidatesPreferMatchingOfficialAlbumAndParseNumbers() throws {
        let track = Track(
            rootID: 1, relativePath: "Beatles/Come Together.mp3", filename: "Come Together.mp3",
            title: "Come Together", artist: "The Beatles", album: "Abbey Road",
            duration: 259, fileSize: 1, modifiedAt: .now, format: "mp3"
        )
        let json = #"""
        {
          "recordings": [{
            "id": "recording-1", "title": "Come Together", "score": 100, "length": 259000,
            "artist-credit": [{"name": "The Beatles", "artist": {"name": "The Beatles"}}],
            "releases": [
              {
                "id": "bootleg", "title": "27 No. 1 Singles", "status": "Bootleg", "date": "2001",
                "artist-credit": [{"name": "The Beatles", "artist": {"name": "The Beatles"}}],
                "media": [{"position": 1, "format": "DVD", "track-count": 27, "track-offset": 24,
                  "track": [{"number": "25", "length": 259000}]}]
              },
              {
                "id": "abbey-road", "title": "Abbey Road", "status": "Official", "date": "1969-09-26",
                "artist-credit": [{"name": "The Beatles", "artist": {"name": "The Beatles"}}],
                "media": [{"position": 1, "format": "CD", "track-count": 17, "track-offset": 0,
                  "track": [{"number": "1", "length": 259000}]}]
              }
            ]
          }]
        }
        """#.data(using: .utf8)!

        let candidates = try MusicBrainzMetadataMatcher.candidates(from: json, matching: track)
        let best = try #require(candidates.first)
        #expect(best.releaseID == "abbey-road")
        #expect(best.album == "Abbey Road")
        #expect(best.albumArtist == "The Beatles")
        #expect(best.discNumber == 1)
        #expect(best.trackNumber == 1)
        #expect(best.mediumTrackCount == 17)
        #expect(best.matchScore > (candidates.last?.matchScore ?? 0))

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        #expect(content.contains("曲名・アーティスト・アルバム名は変更せず"))
        #expect(content.contains("model.autoFillMusicBrainzTrackNumbers"))
        #expect(!content.contains("edit.album = candidate.album"))
    }

    @Test func bundledGenreClassifierWorksWithoutNetworkOrAPIKey() {
        let classifier = LocalGenreClassifier()
        let jazz = Track(
            rootID: 1, relativePath: "Jazz/Bebop/session.mp3", filename: "session.mp3",
            title: "Night Session", artist: "Charlie Parker", album: "Bebop Masters",
            fileSize: 1, modifiedAt: .now, format: "mp3"
        )
        let unknown = Track(
            rootID: 1, relativePath: "misc/song.mp3", filename: "song.mp3",
            title: "Untitled", fileSize: 1, modifiedAt: .now, format: "mp3"
        )
        #expect(classifier.classify(track: jazz).genre == "Jazz")
        #expect(classifier.classify(track: jazz).confidence >= 0.5)
        #expect(classifier.classify(track: unknown).genre == "Other")
        #expect(classifier.classify(track: unknown).confidence < 0.5)
    }

    @Test func paginationKeepsRelativeJumpsAroundFivePageWindow() {
        let entries = PageNavigation.entries(currentPage: 501, pageCount: 1_852)
        #expect(entries.map(\.label) == [
            "-100", "-10",
            "496", "497", "498", "499", "500", "501", "502", "503", "504", "505", "506",
            "+10", "+100", "+1000",
        ])
        #expect(entries.map(\.target) == [
            401, 491,
            496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506,
            511, 601, 1_501,
        ])
    }

    @Test func paginationClampsRelativeJumpsAtFirstAndLastPage() {
        let first = PageNavigation.entries(currentPage: 1, pageCount: 100)
        #expect(first.allSatisfy { $0.kind != .backward })
        #expect(first.map(\.label) == ["1", "2", "3", "4", "5", "6", "+10"])
        let last = PageNavigation.entries(currentPage: 100, pageCount: 100)
        #expect(last.allSatisfy { $0.kind != .forward })
        #expect(last.map(\.label) == ["-10", "95", "96", "97", "98", "99", "100"])
    }

    @Test func migrationEnablesExpectedSchemaAndWAL() throws {
        let context = try TestContext()
        #expect(try context.database.schemaVersion() == 9)
        #expect(try context.database.journalMode().lowercased() == "wal")
    }

    @Test func compilationTagRoundTripsThroughDatabaseAndBatchChanges() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "compilation", title: "Song", isCompilation: true)
        ], sessionID: 1)
        let stored = try #require(try context.database.track(id: 1))
        #expect(stored.isCompilation)

        let changes = BatchMetadataChanges(isCompilation: false)
        let edit = changes.applying(to: stored)
        try context.database.updateTrackMetadata(
            id: stored.id, edit: edit, fileSize: stored.fileSize, modifiedAt: .now
        )
        #expect(try context.database.track(id: 1)?.isCompilation == false)
    }

    @Test func compactBatchEditorAndResizableSummaryColumnsAreWired() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let start = try #require(content.range(of: "private struct BatchTrackMetadataEditor"))
        let editor = String(content[start.lowerBound...])

        #expect(editor.contains("GroupBox(model.text(\"変更する曲情報\""))
        #expect(editor.contains("isCompilation: changeCompilation ? isCompilation : nil"))
        #expect(!editor.contains("LabeledContent(title)"))
        #expect(content.contains("ColumnResizeHandle(width: $albumViewAlbumWidth"))
        #expect(content.contains("ColumnResizeHandle(width: $albumViewArtistWidth"))
        #expect(content.contains("ColumnResizeHandle(width: $albumViewSongsWidth"))
        #expect(model.contains("guard section == requestedSection, selectedArtist?.name == artist.name"))
    }

    @Test func activityLogRecordsFileAndMetadataChangesWithPagingAndFiltering() throws {
        let context = try TestContext()
        let original = context.importedTrack(identity: "logged", title: "Original", filename: "logged.mp3")
        let changed = context.importedTrack(identity: "logged", title: "Changed by Scan", filename: "logged.mp3")
        _ = try context.database.upsertTracks([original], sessionID: 1)
        _ = try context.database.upsertTracks([changed], sessionID: 2)

        let fetchedTrack = try context.database.track(id: 1)
        let track = try #require(fetchedTrack)
        var edit = TrackMetadataEdit(track: track)
        edit.artist = "Edited Artist"
        try context.database.updateTrackMetadata(
            id: track.id, edit: edit, fileSize: track.fileSize, modifiedAt: .now
        )
        _ = try context.database.markMissingTracks(rootID: 1, sessionID: 3)
        #expect(try context.database.removeTrackFromLibrary(id: 1, fileWasTrashed: false))

        let first = try context.database.activityLogPage(offset: 0, limit: 2)
        let second = try context.database.activityLogPage(offset: 2, limit: 10)
        let metadata = try context.database.activityLogPage(kinds: [.metadataChanged])
        let search = try context.database.activityLogPage(query: "logged.mp3")

        #expect(first.totalCount == 5)
        #expect(first.events.count == 2)
        #expect(second.events.count == 3)
        #expect(Set(first.events.map(\.kind) + second.events.map(\.kind)) == Set([
            .added, .fileModified, .metadataChanged, .unavailable, .removedFromLibrary
        ]))
        #expect(metadata.events.count == 1)
        #expect(metadata.events.first?.changes.contains(where: { $0.field == "artist" }) == true)
        #expect(search.totalCount == 5)
        #expect(first.events.first?.relativePath == "Folder/logged.mp3")
    }

    @Test func activityLogRecordsCacheAndMainStorageAdditionsAndKeepsOnlyOneThousandRows() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "storage-log", title: "Storage Log", filename: "storage-log.mp3")
        ], sessionID: 1)

        try context.database.recordTrackActivity(
            trackID: 1, kind: .addedToCache, absolutePath: "/tmp/cache/storage-log.mp3"
        )
        try context.database.recordTrackActivity(
            trackID: 1, kind: .addedToMainStorage, absolutePath: "/Music/storage-log.mp3"
        )
        for index in 0..<1_000 {
            try context.database.recordTrackActivity(
                trackID: 1, kind: .addedToCache, absolutePath: "/tmp/cache/\(index).mp3"
            )
        }

        let firstPage = try context.database.activityLogPage(offset: 0, limit: 100)
        let lastPage = try context.database.activityLogPage(offset: 900, limit: 100)
        #expect(firstPage.totalCount == 1_000)
        #expect(firstPage.events.count == 100)
        #expect(lastPage.events.count == 100)
        #expect(firstPage.events.first?.kind == .addedToCache)
        #expect(firstPage.events.first?.absolutePath == "/tmp/cache/999.mp3")
        #expect(try context.database.trackID(rootID: 1, relativePath: "Folder/storage-log.mp3") == 1)
        #expect(try context.database.trackID(rootID: 2, relativePath: "Folder/storage-log.mp3") == nil)
    }

    @Test func activityLogUsesOneHundredRowPagesAndImportProgressAlwaysResets() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let viewModel = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(viewModel.contains("let activityPageSize = 100"))
        #expect(viewModel.contains("section == .activityLog ? activityPageSize : pageSize"))
        #expect(viewModel.contains("defer { importProgress = .idle }"))
        #expect(viewModel.contains("for (index, sourceURL) in stageURLs.enumerated()"))
    }

    @Test func favoritesAreDynamicAndPaged() throws {
        let context = try TestContext()
        _ = try context.database.insertSyntheticTracks(count: 3)
        #expect(try context.database.toggleFavorite(trackID: 2))
        let page = try context.database.pageFavoriteTracks()
        #expect(page.totalCount == 1)
        #expect(page.tracks.first?.id == 2)
        #expect(page.tracks.first?.isFavorite == true)
    }

    @Test func favoriteOfflineCacheCanBePinnedOutsideRecentLimit() throws {
        let context = try TestContext()
        _ = try context.database.insertSyntheticTracks(count: 2)
        try context.database.recordCachedTrack(trackID: 1, path: "/tmp/recent.mp3", fileSize: 1)
        try context.database.recordCachedTrack(trackID: 2, path: "/tmp/favorite.mp3", fileSize: 1, pinned: true)

        #expect(try context.database.isCachedTrackPinned(trackID: 2))
        #expect(try context.database.cachedTracksBeyondLimit(0).map(\.0) == [1])

        try context.database.setCachedTrackPinned(trackID: 2, pinned: false)
        #expect(try !context.database.isCachedTrackPinned(trackID: 2))
        #expect(Set(try context.database.cachedTracksBeyondLimit(0).map(\.0)) == Set([1, 2]))
    }

    @Test func cachedSongsArePagedAndExposeCurrentPageCacheStatus() throws {
        let context = try TestContext()
        _ = try context.database.insertSyntheticTracks(count: 4)
        try context.database.recordCachedTrack(trackID: 2, path: "/tmp/two.mp3", fileSize: 2_000)
        try context.database.recordCachedTrack(trackID: 4, path: "/tmp/four.mp3", fileSize: 4_000, pinned: true)

        let firstPage = try context.database.pageCachedTracks(
            sort: .title, direction: .ascending, offset: 0, limit: 1
        )
        let secondPage = try context.database.pageCachedTracks(
            sort: .title, direction: .ascending, offset: 1, limit: 1
        )

        #expect(firstPage.totalCount == 2)
        #expect(firstPage.tracks.count == 1)
        #expect(secondPage.totalCount == 2)
        #expect(secondPage.tracks.count == 1)
        #expect(Set(firstPage.tracks.map(\.id) + secondPage.tracks.map(\.id)) == Set([2, 4]))
        #expect(try context.database.cachedTrackIDs(in: [1, 2, 3, 4]) == Set([2, 4]))
        #expect(try context.database.cachedTrackIDs(in: []) == [])
    }

    @Test func settingsImportsAndLyricsRoundTrip() throws {
        let context = try TestContext()
        try context.database.setSetting("24", forKey: "cache.trackLimit")
        #expect(try context.database.setting(forKey: "cache.trackLimit") == "24")
        let importID = try context.database.addPendingImport(localPath: "/tmp/song.mp3", filename: "song.mp3")
        #expect(try context.database.pendingImports().first?.id == importID)
        _ = try context.database.insertSyntheticTracks(count: 1)
        try context.database.saveLyrics(trackID: 1, provider: "test", plain: "hello", synced: nil)
        #expect(try context.database.cachedLyrics(trackID: 1)?.plainLyrics == "hello")
    }

    @Test func duplicateIdentityUpdatesWithoutAddingAnotherTrack() throws {
        let context = try TestContext()
        let original = context.importedTrack(identity: "same", title: "Original")
        let updated = context.importedTrack(identity: "same", title: "Updated")

        _ = try context.database.upsertTracks([original], sessionID: 1)
        _ = try context.database.upsertTracks([updated], sessionID: 2)

        #expect(try context.database.trackCount() == 1)
        #expect(try context.database.pageTracks().tracks.first?.title == "Updated")
    }

    @Test func removedTrackStaysExcludedFromFutureScans() throws {
        let context = try TestContext()
        let item = context.importedTrack(identity: "excluded", title: "Removed")
        _ = try context.database.upsertTracks([item], sessionID: 1)
        #expect(try context.database.removeTrackFromLibrary(id: 1, fileWasTrashed: false))
        #expect(try context.database.trackCount() == 0)
        #expect(try context.database.isExcluded(identityKey: "excluded"))

        _ = try context.database.upsertTracks([item], sessionID: 2)
        #expect(try context.database.trackCount() == 0)
    }

    @Test func metadataEditUpdatesFTSAtomically() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks(
            [context.importedTrack(identity: "editable", title: "Old Title")], sessionID: 1
        )
        let fetched = try context.database.track(id: 1)
        let track = try #require(fetched)
        var edit = TrackMetadataEdit(track: track)
        edit.title = "Northern Rewrite"
        edit.artist = "Edited Artist"
        edit.artworkData = Data([0xFF, 0xD8, 0xFF, 0xD9])
        try context.database.updateTrackMetadata(
            id: track.id, edit: edit, fileSize: track.fileSize, modifiedAt: track.modifiedAt
        )
        #expect(try context.database.pageTracks(query: "Northern").totalCount == 1)
        #expect(try context.database.pageTracks(query: "Old").totalCount == 0)
        #expect(try context.database.track(id: track.id)?.hasArtwork == true)
    }

    @Test func leadingTitleSpaceCleanupCandidatesAreKeysetPaged() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "half", title: " Half", filename: "half.mp3"),
            context.importedTrack(identity: "clean", title: "Clean", filename: "clean.mp3"),
            context.importedTrack(identity: "full", title: "　Full", filename: "full.m4a", format: "m4a")
        ], sessionID: 1)

        let first = try context.database.tracksWithLeadingTitleSpaces(afterID: 0, limit: 1)
        let second = try context.database.tracksWithLeadingTitleSpaces(afterID: try #require(first.first?.id), limit: 1)

        #expect(first.map(\.title) == [" Half"])
        #expect(second.map(\.title) == ["　Full"])
        #expect(try context.database.tracksWithLeadingTitleSpaces(afterID: try #require(second.first?.id), limit: 1).isEmpty)
    }

    @Test func fullTextSearchFindsMetadataAndFilename() throws {
        let context = try TestContext()
        let importItem = context.importedTrack(
            identity: "fts", title: "Northern Lights", artist: "Aurora Unit",
            album: "Night Drive", filename: "special-mix.mp3"
        )
        _ = try context.database.upsertTracks([importItem], sessionID: 1)

        #expect(try context.database.pageTracks(query: "Aurora").totalCount == 1)
        #expect(try context.database.pageTracks(query: "special").totalCount == 1)
        #expect(try context.database.pageTracks(query: "missing").totalCount == 0)
    }

    @Test func playlistStoresTrackIDsInStableOrderAndCanReorder() throws {
        let context = try TestContext()
        _ = try context.database.insertSyntheticTracks(count: 5)
        let all = try context.database.pageTracks(limit: 5).tracks
        let playlistID = try context.database.createPlaylist(name: "Order")
        _ = try context.database.addTracks(all.map(\.id), toPlaylist: playlistID)

        try context.database.movePlaylistItem(playlistID: playlistID, from: 0, to: 3)
        let reordered = try context.database.playlistTracks(playlistID: playlistID, offset: 0, limit: 5)

        #expect(reordered.tracks.count == 5)
        #expect(reordered.tracks[3].id == all[0].id)
    }

    @Test func persistentPlayQueueKeepsOrderPagesAndDequeuesOneItem() throws {
        let context = try TestContext()
        _ = try context.database.insertSyntheticTracks(count: 4)
        #expect(try context.database.enqueueNext(trackID: 3))
        #expect(try context.database.enqueueNext(trackID: 1))
        #expect(try context.database.enqueueNext(trackID: 3))

        let firstPage = try context.database.playQueuePage(limit: 2)
        #expect(firstPage.totalCount == 3)
        #expect(firstPage.tracks.map(\.id) == [3, 1])
        #expect(try context.database.dequeueNext()?.id == 3)
        #expect(try context.database.playQueuePage().tracks.map(\.id) == [1, 3])

        try context.database.removeFromPlayQueue(trackID: 3)
        #expect(try context.database.playQueuePage().tracks.map(\.id) == [1])
        try context.database.clearPlayQueue()
        #expect(try context.database.playQueuePage().totalCount == 0)
    }

    @Test func largePlaylistIsChunkedAndPaged() throws {
        let context = try TestContext()
        _ = try context.database.insertSyntheticTracks(count: 10_500)
        let playlistID = try context.database.createPlaylist(name: "Large")
        let added = try context.database.addTracks(Int64(1)...Int64(10_500), toPlaylist: playlistID)

        let page = try context.database.playlistTracks(playlistID: playlistID, offset: 10_000, limit: 200)
        #expect(added == 10_500)
        #expect(page.tracks.count == 200)
        #expect(page.totalCount == 10_500)
    }

    @Test func shuffleCandidatesAreBoundedAndDoNotMaterializeLibrary() throws {
        let context = try TestContext()
        _ = try context.database.insertSyntheticTracks(count: 8_000)
        let candidates = try context.database.shuffleCandidates(afterID: 0, seed: 42, limit: 25)

        #expect(candidates.count <= 25)
        #expect(Set(candidates.map(\.id)).count == candidates.count)
    }

    @Test func keysetPagingReturnsNextPageWithoutOverlap() throws {
        let context = try TestContext()
        _ = try context.database.insertSyntheticTracks(count: 1_000)
        let first = try context.database.pageTracksAfter(sort: .artist, after: nil, limit: 200)
        let second = try context.database.pageTracksAfter(
            sort: .artist, after: first.tracks.last, logicalOffset: 200, limit: 200,
            knownTotal: first.totalCount
        )

        #expect(first.tracks.count == 200)
        #expect(second.tracks.count == 200)
        #expect(Set(first.tracks.map(\.id)).isDisjoint(with: second.tracks.map(\.id)))
    }

    @Test func playbackSequenceFollowsVisibleAlbumOrderInBothDirections() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "one", title: "One", artist: "Band", album: "Record", filename: "one.mp3", trackNumber: 1),
            context.importedTrack(identity: "two", title: "Two", artist: "Band", album: "Record", filename: "two.mp3", trackNumber: 2),
            context.importedTrack(identity: "three", title: "Three", artist: "Band", album: "Record", filename: "three.mp3", trackNumber: 3),
            context.importedTrack(identity: "other", title: "Other", artist: "Band", album: "Other Record", filename: "other.mp3", trackNumber: 3)
        ], sessionID: 1)
        let album = AlbumSummary(name: "Record", artist: "Band", trackCount: 3)
        let ordered = try context.database.pageTracksForAlbum(album: album, sort: .trackNumber).tracks
        let sequence = TrackPlaybackContext(
            scope: .album(name: album.name, artist: album.artist),
            sort: .trackNumber,
            direction: .ascending
        )

        let next = try context.database.adjacentTrack(in: sequence, from: ordered[1], direction: 1)
        let previous = try context.database.adjacentTrack(in: sequence, from: ordered[1], direction: -1)

        #expect(next?.title == "Three")
        #expect(previous?.title == "One")
    }

    @Test func playbackSequenceCrossesPageBoundaryWithoutBuildingAGiantQueue() throws {
        let context = try TestContext()
        _ = try context.database.insertSyntheticTracks(count: 405)
        let pageEnd = try context.database.pageTracks(sort: .title, offset: 199, limit: 1).tracks[0]
        let expected = try context.database.pageTracks(sort: .title, offset: 200, limit: 1).tracks[0]
        let sequence = TrackPlaybackContext(scope: .library(query: ""), sort: .title, direction: .ascending)

        let next = try context.database.adjacentTrack(in: sequence, from: pageEnd, direction: 1)

        #expect(next?.id == expected.id)
        #expect(try context.database.playQueuePage().totalCount == 0)
    }

    @Test func descendingKeysetSortIsStable() throws {
        let context = try TestContext()
        _ = try context.database.insertSyntheticTracks(count: 1_000)
        let first = try context.database.pageTracksAfter(sort: .title, direction: .descending, after: nil, limit: 200)
        let second = try context.database.pageTracksAfter(
            sort: .title, direction: .descending, after: first.tracks.last,
            logicalOffset: 200, limit: 200, knownTotal: first.totalCount
        )
        #expect(first.tracks.count == 200)
        #expect(second.tracks.count == 200)
        #expect(Set(first.tracks.map(\.id)).isDisjoint(with: second.tracks.map(\.id)))
        #expect(first.tracks.first!.title.localizedCaseInsensitiveCompare(first.tracks.last!.title) != .orderedAscending)
    }

    @Test func discAndTrackNumberSortsAreNumericAndPaged() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "d2t1", title: "Disc Two", filename: "d2.mp3", discNumber: 2, trackNumber: 1),
            context.importedTrack(identity: "d1t10", title: "Track Ten", filename: "t10.mp3", discNumber: 1, trackNumber: 10),
            context.importedTrack(identity: "d1t2", title: "Track Two", filename: "t2.mp3", discNumber: 1, trackNumber: 2)
        ], sessionID: 1)

        let byDisc = try context.database.pageTracksAfter(sort: .discNumber, after: nil, limit: 10)
        let byTrack = try context.database.pageTracksAfter(sort: .trackNumber, after: nil, limit: 10)

        #expect(byDisc.tracks.map { [$0.discNumber, $0.trackNumber] } == [[1, 2], [1, 10], [2, 1]])
        #expect(byTrack.tracks.map(\.trackNumber) == [1, 2, 10])
    }

    @Test func albumAndArtistSummariesArePagedAndCounted() throws {
        let context = try TestContext()
        let imports = [
            context.importedTrack(identity: "one", title: "One", artist: "Artist A", album: "Album A", filename: "one.mp3"),
            context.importedTrack(identity: "two", title: "Two", artist: "Artist A", album: "Album A", filename: "two.mp3"),
            context.importedTrack(identity: "three", title: "Three", artist: "Artist A", album: "Album B", filename: "three.mp3")
        ]
        _ = try context.database.upsertTracks(imports, sessionID: 1)
        let artists = try context.database.pageArtists()
        let albums = try context.database.pageAlbums(artistFilter: "Artist A")
        #expect(artists.artists.first?.trackCount == 3)
        #expect(artists.artists.first?.albumCount == 2)
        #expect(albums.totalCount == 2)
        #expect(albums.albums.first(where: { $0.name == "Album A" })?.trackCount == 2)
        #expect(try context.database.albumTrackCount(album: "album a", artist: "artist a") == 2)
        let albumTracks = try context.database.pageTracksForAlbum(album: AlbumSummary(name: "Album A", artist: "Artist A", trackCount: 2))
        #expect(albumTracks.totalCount == 2)
    }

    @Test func metadataVariationLinkUsesExactFieldAndValue() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "exact", title: "One", album: "Same", filename: "one.mp3"),
            context.importedTrack(identity: "case", title: "Two", album: "same", filename: "two.mp3"),
            context.importedTrack(identity: "other", title: "Same", album: "Other", filename: "three.mp3")
        ], sessionID: 1)

        let page = try context.database.pageTracks(matching: ExactMetadataFilter(field: .album, value: "Same"))
        #expect(page.totalCount == 1)
        #expect(page.tracks.map(\.filename) == ["one.mp3"])

        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        #expect(content.contains("searchVariationValue(candidate.valueA, field: candidate.field)"))
        #expect(content.contains("searchVariationValue(candidate.valueB, field: candidate.field)"))
        #expect(model.contains("changeSection(.tracks, exactFilter: ExactMetadataFilter(field: field, value: value))"))
    }

    @Test func storageSummaryAggregatesBytesAndAbsoluteRootsWithoutLoadingTracks() throws {
        let context = try TestContext()
        let rootID = try context.database.addScanRoot(
            displayName: "Music", bookmark: Data(), volumeUUID: "test-volume", path: context.directory.path
        )
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "one", title: "One", artist: "Artist A", album: "Album A", filename: "one.mp3", rootID: rootID),
            context.importedTrack(identity: "two", title: "Two", artist: "Artist A", album: "Album A", filename: "two.mp3", rootID: rootID),
            context.importedTrack(identity: "three", title: "Three", artist: "Artist B", album: "Album B", filename: "three.mp3", rootID: rootID)
        ], sessionID: 1)

        let library = try context.database.libraryStorageSummary()
        let album = try context.database.libraryStorageSummary(
            albumFilter: AlbumSummary(name: "Album A", artist: "Artist A", trackCount: 2)
        )
        let artist = try context.database.libraryStorageSummary(artistFilter: "Artist A")

        #expect(library.totalBytes == 3_072)
        #expect(library.absoluteRootPaths == [context.directory.path])
        #expect(album.totalBytes == 2_048)
        #expect(artist.totalBytes == 2_048)
    }

    @Test func facetPagesReportExactTotalInsteadOfNextPageEstimate() throws {
        let context = try TestContext()
        _ = try context.database.insertSyntheticTracks(count: 1_000)
        let page = try context.database.facetPage(section: .genres, offset: 10, limit: 5)
        #expect(page.facets.count == 5)
        #expect(page.offset == 10)
        #expect(page.totalCount == 40)
    }

    @Test func genreDetailPagesOnlyReturnMatchingAlbumsArtistsAndTracks() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "rock-1", title: "Rock One", artist: "Amp", album: "Loud", genre: "Rock", filename: "rock-1.mp3"),
            context.importedTrack(identity: "rock-2", title: "Rock Two", artist: "Amp", album: "Loud", genre: "Rock", filename: "rock-2.mp3"),
            context.importedTrack(identity: "rock-3", title: "Rock Three", artist: "Stone", album: "Granite", genre: "Rock", filename: "rock-3.mp3"),
            context.importedTrack(identity: "jazz-1", title: "Jazz One", artist: "Blue", album: "Night", genre: "Jazz", filename: "jazz-1.mp3")
        ], sessionID: 1)

        let albums = try context.database.pageAlbums(genreFilter: "rock")
        let artists = try context.database.pageArtists(genreFilter: "ROCK")
        let tracks = try context.database.pageTracksForGenre(genre: "Rock", limit: 2)

        #expect(albums.totalCount == 2)
        #expect(Set(albums.albums.map(\.name)) == ["Loud", "Granite"])
        #expect(artists.totalCount == 2)
        #expect(Set(artists.artists.map(\.name)) == ["Amp", "Stone"])
        #expect(tracks.totalCount == 3)
        #expect(tracks.tracks.count == 2)
        #expect(tracks.tracks.allSatisfy { $0.genre == "Rock" })
    }

    @Test func alphabeticalOffsetsJumpToLatinKanaAndNumericEntries() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "numeric", title: "0 Zero", artist: "1 Artist", album: "2 Album", filename: "0.mp3"),
            context.importedTrack(identity: "alpha", title: "Alpha", artist: "Alpha Artist", album: "Alpha Album", filename: "a.mp3"),
            context.importedTrack(identity: "beta", title: "Beta", artist: "Beta Artist", album: "Beta Album", filename: "b.mp3"),
            context.importedTrack(identity: "kana-a", title: "あさ", artist: "あお", album: "あさ", filename: "kana-a.mp3"),
            context.importedTrack(identity: "kana-ka", title: "かぜ", artist: "かお", album: "かぜ", filename: "kana-ka.mp3")
        ], sessionID: 1)

        let titleOffset = try context.database.offsetForTrackTitle(startingAt: "B")
        #expect(try context.database.pageTracks(sort: .title, offset: titleOffset, limit: 1).tracks.first?.title == "Beta")
        let kanaTitleOffset = try context.database.offsetForTrackTitle(startingAt: "か")
        #expect(try context.database.pageTracks(sort: .title, offset: kanaTitleOffset, limit: 1).tracks.first?.title == "かぜ")
        let artistOffset = try context.database.offsetForArtist(startingAt: "A")
        #expect(try context.database.pageArtists(offset: artistOffset, limit: 1).artists.first?.name == "Alpha Artist")
        let albumOffset = try context.database.offsetForAlbum(startingAt: "あ")
        #expect(try context.database.pageAlbums(offset: albumOffset, limit: 1).albums.first?.name == "あさ")
    }

    @Test func artistSearchAndAlphabeticalOrderIgnoreLeadingThe() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "alpha", title: "One", artist: "Alpha", filename: "a.mp3"),
            context.importedTrack(identity: "beatles", title: "Two", artist: "The Beatles", filename: "b.mp3"),
            context.importedTrack(identity: "clash", title: "Three", artist: "the Clash", filename: "c.mp3")
        ], sessionID: 1)

        let all = try context.database.pageArtists()
        #expect(all.artists.map(\.name) == ["Alpha", "The Beatles", "the Clash"])
        let withoutArticle = try context.database.pageArtists(search: "Beatles")
        #expect(withoutArticle.artists.map(\.name) == ["The Beatles"])
        let bOffset = try context.database.offsetForArtist(startingAt: "B")
        #expect(try context.database.pageArtists(offset: bOffset, limit: 1).artists.first?.name == "The Beatles")
    }

    @Test func unknownArtistIsLogicalPagedGroupWithoutChangingEmptyTag() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "unknown-1", title: "One", artist: "", album: "Album A", filename: "one.mp3"),
            context.importedTrack(identity: "unknown-2", title: "Two", artist: "", album: "", filename: "two.mp3"),
            context.importedTrack(identity: "known", title: "Three", artist: "Known", filename: "three.mp3")
        ], sessionID: 1)

        let artists = try context.database.pageArtists()
        let unknown = try #require(artists.artists.first(where: { $0.name.isEmpty }))
        let page = try context.database.pageTracksForArtist(artist: "", limit: 1)

        #expect(unknown.trackCount == 2)
        #expect(unknown.albumCount == 1)
        #expect(page.totalCount == 2)
        #expect(page.tracks.count == 1)
        #expect(page.tracks[0].artist.isEmpty)
    }

    @Test func metadataDiagnosticsCountAndPageMissingAndURLValues() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "missing", title: "", artist: "", album: "", filename: "missing.mp3"),
            context.importedTrack(identity: "url", title: "Tagged", genre: "http://example.invalid", filename: "url.mp3"),
            context.importedTrack(identity: "mojibake", title: "I ĐAÈA  ÔÌ¼", artist: "Artist", album: "Album", filename: "garbled.mp3"),
            context.importedTrack(identity: "clean", title: "Clean", filename: "clean.m4a", format: "m4a")
        ], sessionID: 1)

        let summaries = try context.database.metadataIssueSummaries()
        #expect(summaries.first(where: { $0.kind == .missingTitle })?.count == 1)
        #expect(summaries.first(where: { $0.kind == .missingArtist })?.count == 1)
        #expect(summaries.first(where: { $0.kind == .missingAlbum })?.count == 1)
        #expect(summaries.first(where: { $0.kind == .urlInMP3Metadata })?.count == 1)
        #expect(summaries.first(where: { $0.kind == .suspectedMojibake })?.count == 1)
        #expect(try context.database.pageMetadataIssues(kind: .urlInMP3Metadata).tracks.first?.filename == "url.mp3")
        #expect(try context.database.pageMetadataIssues(kind: .suspectedMojibake).tracks.first?.filename == "garbled.mp3")
    }

    @Test func duplicateMetadataDiagnosticsUseBoundedGroupAggregation() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "duplicate-1", title: "Same", artist: "Artist", album: "Album", filename: "one.mp3"),
            context.importedTrack(identity: "duplicate-2", title: "same", artist: "artist", album: "album", filename: "two.mp3"),
            context.importedTrack(identity: "unique", title: "Other", artist: "Artist", album: "Album", filename: "three.mp3")
        ], sessionID: 1)

        let summaries = try context.database.metadataIssueSummaries()
        let page = try context.database.pageMetadataIssues(kind: .duplicateTracks)

        #expect(summaries.first(where: { $0.kind == .duplicateTracks })?.count == 2)
        #expect(page.totalCount == 2)
        #expect(Set(page.tracks.map(\.filename)) == ["one.mp3", "two.mp3"])
    }

    @Test func metadataNavigationCancelsStaleSummaryAndPageLoads() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(source.contains("pageLoadTask?.cancel()"))
        #expect(source.contains("metadataSummaryTask?.cancel()"))
        #expect(source.contains("catch is CancellationError"))
        #expect(source.contains("guard !Task.isCancelled else { return }"))
    }

    @Test func duplicateDiagnosticsProvideCheckboxesAndConfirmedBulkDeletion() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(source.contains("private var isDuplicateSelectionMode: Bool"))
        #expect(source.contains("private func duplicateSelectionCheckbox"))
        #expect(source.contains("model.selectedTrackIDs.formUnion(model.tracks.map(\\.id))"))
        #expect(source.contains("tracksPendingDeletion = selectedTracksOnPage"))
        #expect(source.contains("選択した\\(selectedTracksOnPage.count)曲を削除…"))
        #expect(source.contains("ライブラリからのみ削除"))
        #expect(source.contains("実ファイルをゴミ箱へ移動"))
    }

    @Test func commandASelectsOnlyTheFocusedVisibleTrackPage() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(source.contains("@FocusState private var isTrackTableFocused: Bool"))
        #expect(source.contains("private func selectAllVisibleTracks()"))
        #expect(source.contains("model.selectedTrackIDs = Set(model.tracks.map(\\.id))"))
        #expect(source.contains(".focused($isTrackTableFocused)"))
        #expect(source.contains(".onKeyPress(\"a\", phases: .down)"))
        #expect(source.contains("keyPress.modifiers.contains(.command)"))
    }

    @Test func cacheRetentionLimitCanBeTypedAndStepped() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(source.contains("private struct CacheTrackLimitControl: View"))
        #expect(source.contains("TextField(\"\", value: $value, format: .number)"))
        #expect(source.contains("Stepper(value: $value, in: limits)"))
        #expect(source.components(separatedBy: "CacheTrackLimitControl(").count - 1 >= 2)
    }

    @Test func flacImportDoesNotBlockOnProcessWaitAndAddsPlaylistItemsIncrementally() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let services = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryServices.swift"))
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))

        #expect(!services.contains("process.waitUntilExit()"))
        #expect(services.contains("let terminationStatus = process.terminationStatus"))
        #expect(model.contains("try recordImportedTrack(trackID)"))
        #expect(model.contains("try self.database.addTracks([trackID], toPlaylist: playlistID)"))
    }

    @Test func recentDateUpNextAndAutomaticGenreUIAreWired() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(contentsOf: sourceRoot.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let model = try String(contentsOf: sourceRoot.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let models = try String(contentsOf: sourceRoot.appending(path: "Sources/MassiveMusicCore/Models.swift"))

        #expect(content.contains("case .recentlyAdded: \"clock.fill\""))
        #expect(content.contains("columns.addedDate.visible"))
        #expect(content.contains("header(.dateAdded)"))
        #expect(content.contains("formatAddedDate(track.addedAt)"))
        #expect(models.contains("case upNext = \"次に再生\""))
        #expect(content.contains("UpNextLibraryView(model: model, player: player)"))
        #expect(!content.contains("Text(model.text(\"次に再生\", \"Up Next\")).tag(3)"))
        #expect(model.contains("func autoClassifyGenreIfNeeded(for track: Track)"))
    }

    @Test func metadataEditorSavesBeforeSequentialNavigation() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let content = try String(
            contentsOf: sourceRoot.appending(path: "Sources/MassiveMusic/ContentView.swift"),
            encoding: .utf8
        )
        let model = try String(
            contentsOf: sourceRoot.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"),
            encoding: .utf8
        )

        #expect(content.contains("saveAndNavigate(by: -1)"))
        #expect(content.contains("saveAndNavigate(by: 1)"))
        #expect(content.contains("guard await saveCurrentTrack() else { return }"))
        #expect(content.contains("Text(positionLabel)"))
        #expect(content.contains("keyboardShortcut(\"]\", modifiers: .command)"))
        #expect(model.contains("func updateMetadataFromEditor"))
    }

    @Test func successfullyEditedTrackSnapshotUsesWrittenMetadata() throws {
        let context = try TestContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "sequential-editor", title: "Before")
        ], sessionID: 1)
        let fetchedTrack = try context.database.track(id: 1)
        let track = try #require(fetchedTrack)
        var edit = TrackMetadataEdit(track: track)
        edit.title = "After"
        edit.artist = "Edited Artist"
        edit.album = "Edited Album"
        edit.discNumber = 2
        edit.trackNumber = 7
        edit.isCompilation = true

        let updated = track.applying(edit)

        #expect(updated.id == track.id)
        #expect(updated.relativePath == track.relativePath)
        #expect(updated.title == "After")
        #expect(updated.artist == "Edited Artist")
        #expect(updated.album == "Edited Album")
        #expect(updated.discNumber == 2)
        #expect(updated.trackNumber == 7)
        #expect(updated.isCompilation)
    }

    @Test func genreSuggestionRegistersWithoutMountedSourceAndOnlyWritesExistingFiles() throws {
        let context = try TestContext()
        defer { try? FileManager.default.removeItem(at: context.directory) }
        _ = try context.database.upsertTracks([
            context.importedTrack(
                identity: "genre-offline", title: "Arrogant Boy",
                artist: "Deep Purple", album: "SPLAT!", filename: "missing.mp3"
            )
        ], sessionID: 1)
        let storedTrackID = try context.database.trackID(forIdentityKey: "genre-offline")
        let trackID = try #require(storedTrackID)

        try context.database.updateTrackGenre(id: trackID, genre: "Hard Rock")
        #expect(try context.database.track(id: trackID)?.genre == "Hard Rock")

        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let model = try String(contentsOf: sourceRoot.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let services = try String(contentsOf: sourceRoot.appending(path: "Sources/MassiveMusic/LibraryServices.swift"))
        let content = try String(contentsOf: sourceRoot.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        #expect(model.contains("try self.database.updateTrackGenre(id: track.id, genre: genre)"))
        #expect(model.contains("await trackFiles.sourceFileIsAvailable(for: track)"))
        #expect(services.contains("func sourceFileIsAvailable(for track: Track) -> Bool"))
        #expect(content.contains("ライブラリへ登録"))
    }

    @Test func metadataVariationAnalyzerFindsNormalizationAndLikelyTypo() async throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks([
            context.importedTrack(identity: "a", title: "Song A", artist: "Prince", filename: "a.mp3"),
            context.importedTrack(identity: "b", title: "Song B", artist: "Ｐｒｉｎｃｅ", filename: "b.mp3"),
            context.importedTrack(identity: "c", title: "Song C", artist: "Prinve", filename: "c.mp3")
        ], sessionID: 1)

        #expect(MetadataNormalizer.key("Ｐｒｉｎｃｅ ") == MetadataNormalizer.key("Prince"))
        #expect(MetadataNormalizer.editDistance("prince", "prinve") == 1)
        try await MetadataDiagnosticsAnalyzer(database: context.database).analyze()
        let candidates = try context.database.pageMetadataVariations(limit: 20).candidates

        #expect(candidates.contains(where: { $0.reason == .normalization }))
        #expect(candidates.contains(where: { $0.reason == .likelyTypo && $0.field == .artist }))
    }

    @Test func failedTransactionRollsBack() throws {
        let context = try TestContext()
        #expect(try context.database.rollbackProbeForTesting())
        #expect(try context.database.trackCount() == 0)
    }

    @Test func unavailableTracksAreMarkedWithoutDeletion() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks(
            [context.importedTrack(identity: "missing", title: "Missing", rootID: 7)],
            sessionID: 1
        )
        let marked = try context.database.markMissingTracks(rootID: 7, sessionID: 2)

        #expect(marked == 1)
        #expect(try context.database.trackCount() == 1)
        #expect(try context.database.track(id: 1)?.isAvailable == false)
    }

    @Test func aSingleMissingSourceCanBeMarkedUnavailableWithoutDeletingIt() throws {
        let context = try TestContext()
        _ = try context.database.upsertTracks(
            [context.importedTrack(identity: "missing-file", title: "Missing File", rootID: 7)],
            sessionID: 1
        )

        try context.database.setTrackAvailability(id: 1, isAvailable: false)

        #expect(try context.database.trackCount() == 1)
        #expect(try context.database.track(id: 1)?.isAvailable == false)
    }

    @Test func disconnectedOrMissingTracksAreWarnedBeforePlayback() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let model = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/LibraryViewModel.swift"))
        let content = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let playback = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/PlaybackController.swift"))

        #expect(model.contains("func isTrackPlayable(_ track: Track) -> Bool"))
        #expect(model.contains("unavailableRootIDs.contains(track.rootID)"))
        #expect(model.contains("missingVisibleTrackIDs.contains(track.id)"))
        #expect(model.contains("await refreshVisibleTrackAvailability()"))
        #expect(model.contains("let visibleTracks = tracks"))
        #expect(content.contains("let isPlayable = model.isTrackPlayable(track)"))
        #expect(content.contains("!player.unavailableTrackIDs.contains(track.id) || model.isCached(track)"))
        #expect(content.contains("externaldrive.badge.exclamationmark"))
        #expect(content.contains("foregroundStyle(Color.orange)"))
        #expect(playback.contains("database.setTrackAvailability(id: track.id, isAvailable: false)"))
        #expect(playback.contains("let sourceDisappeared = resolvedSourceURL.map"))
        #expect(playback.contains("元ファイルが見つからず、ローカルキャッシュもありません"))
    }

    @Test func interruptedSessionIsResumable() throws {
        let context = try TestContext()
        let rootID = try context.database.addScanRoot(
            displayName: "Test", bookmark: Data(), volumeUUID: "test-volume", path: context.directory.path
        )
        let sessionID = try context.database.createScanSession(rootID: rootID)
        try context.database.updateScanSession(
            id: sessionID, state: .paused, cursor: "folder/track-050.mp3",
            discovered: 50, processed: 50, changed: 50, skipped: 0, errors: 0
        )

        let resumable = try context.database.resumableSession(rootID: rootID)
        #expect(resumable?.id == sessionID)
        #expect(resumable?.cursor == "folder/track-050.mp3")
    }
}

private struct TestContext {
    let directory: URL
    let database: LibraryDatabase

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "MassiveMusicTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        database = try LibraryDatabase(url: directory.appending(path: "test.sqlite"))
    }

    func importedTrack(
        identity: String,
        title: String,
        artist: String = "Artist",
        album: String = "Album",
        genre: String = "",
        isCompilation: Bool = false,
        filename: String = "track.mp3",
        format: String = "mp3",
        rootID: Int64 = 1,
        discNumber: Int? = nil,
        trackNumber: Int? = nil,
        addedAt: Date = Date()
    ) -> TrackImport {
        TrackImport(
            identityKey: identity,
            fileResourceID: identity,
            track: Track(
                rootID: rootID,
                relativePath: "Folder/\(filename)",
                filename: filename,
                title: title,
                artist: artist,
                album: album,
                genre: genre,
                isCompilation: isCompilation,
                discNumber: discNumber,
                trackNumber: trackNumber,
                fileSize: 1_024,
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                format: format,
                addedAt: addedAt
            )
        )
    }
}
