import Foundation
import Testing
@testable import MassiveMusicCore

@Suite(.serialized)
struct LibraryDatabaseTests {
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

    @Test func bottomPlayerSharesArtworkAndUsesAnInsetThatCannotBeClipped() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))

        #expect(source.contains("private struct PlayerArtwork: View"))
        #expect(source.components(separatedBy: "PlayerArtwork(").count - 1 >= 2)
        #expect(source.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))
        #expect(!source.contains("PlayerBar(player: player, model: model)\n                .fixedSize"))
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

    @Test func openingSettingsDoesNotImplicitlyAuthenticateAIProviders() throws {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: repository.appending(path: "Sources/MassiveMusic/ContentView.swift"))
        let settingsStart = try #require(source.range(of: "private struct LibrarySettingsView: View"))
        let settingsEnd = try #require(source.range(of: "\nprivate struct FeatureStatusView", range: settingsStart.upperBound..<source.endIndex))
        let settings = String(source[settingsStart.lowerBound..<settingsEnd.lowerBound])
        let appearStart = try #require(settings.range(of: "        .onAppear {"))
        let appearEnd = try #require(settings.range(of: "\n        }", range: appearStart.upperBound..<settings.endIndex))
        let onAppear = String(settings[appearStart.lowerBound..<appearEnd.upperBound])

        #expect(!onAppear.contains("validateAIProviders"))
        #expect(settings.contains("Button(model.text(\"接続を再確認\", \"Test Connections\"), action: model.validateAIProviders)"))
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

    @Test func backFromArtistRestoresThePreviousTrackIndexAndPage() throws {
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
        #expect(best.matchScore > (candidates.last?.matchScore ?? 0))
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
            "-1000", "-100", "-10",
            "496", "497", "498", "499", "500", "501", "502", "503", "504", "505", "506",
            "+10", "+100", "+1000",
        ])
        #expect(entries.map(\.target) == [
            1, 401, 491,
            496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506,
            511, 601, 1_501,
        ])
    }

    @Test func paginationClampsRelativeJumpsAtFirstAndLastPage() {
        let first = PageNavigation.entries(currentPage: 1, pageCount: 100)
        #expect(Array(first.prefix(3).map(\.target)) == [1, 1, 1])
        let last = PageNavigation.entries(currentPage: 100, pageCount: 100)
        #expect(Array(last.suffix(3).map(\.target)) == [100, 100, 100])
    }

    @Test func migrationEnablesExpectedSchemaAndWAL() throws {
        let context = try TestContext()
        #expect(try context.database.schemaVersion() == 7)
        #expect(try context.database.journalMode().lowercased() == "wal")
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
        let albumTracks = try context.database.pageTracksForAlbum(album: AlbumSummary(name: "Album A", artist: "Artist A", trackCount: 2))
        #expect(albumTracks.totalCount == 2)
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
            context.importedTrack(identity: "clean", title: "Clean", filename: "clean.m4a", format: "m4a")
        ], sessionID: 1)

        let summaries = try context.database.metadataIssueSummaries()
        #expect(summaries.first(where: { $0.kind == .missingTitle })?.count == 1)
        #expect(summaries.first(where: { $0.kind == .missingArtist })?.count == 1)
        #expect(summaries.first(where: { $0.kind == .missingAlbum })?.count == 1)
        #expect(summaries.first(where: { $0.kind == .urlInMP3Metadata })?.count == 1)
        #expect(try context.database.pageMetadataIssues(kind: .urlInMP3Metadata).tracks.first?.filename == "url.mp3")
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
        filename: String = "track.mp3",
        format: String = "mp3",
        rootID: Int64 = 1,
        discNumber: Int? = nil,
        trackNumber: Int? = nil
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
                discNumber: discNumber,
                trackNumber: trackNumber,
                fileSize: 1_024,
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                format: format
            )
        )
    }
}
