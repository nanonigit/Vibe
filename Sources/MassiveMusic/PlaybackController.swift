@preconcurrency import AVFoundation
import Combine
import Foundation
import MassiveMusicCore
@preconcurrency import MediaPlayer

@MainActor
final class PlaybackController: ObservableObject {
    enum RepeatMode: String, CaseIterable {
        case off = "リピートなし"
        case all = "全体リピート"
        case one = "1曲リピート"
    }

    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var duration: Double = 0
    @Published var volume: Double = 0.8 {
        didSet { player.volume = Float(max(0, min(1, volume))) }
    }
    @Published var repeatMode: RepeatMode = .off
    @Published var shuffleEnabled = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var upNextTracks: [Track] = []
    @Published private(set) var queueTotalCount = 0
    @Published private(set) var queueOffset = 0

    let queuePageSize = 100

    private let database: LibraryDatabase
    private let offlineCache: OfflineCacheManager
    private let player = AVPlayer()
    private var periodicObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var activeScopedURL: URL?
    private var activeScopeStarted = false
    private var loadToken = UUID()
    private var shuffleSeed = Int64.random(in: 1...Int64.max)
    private var sequenceContext: TrackPlaybackContext?
    private var sequenceCursor: Track?

    init(database: LibraryDatabase) {
        self.database = database
        offlineCache = OfflineCacheManager(database: database)
        player.volume = Float(volume)
        periodicObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                self?.elapsed = time.seconds.isFinite ? max(0, time.seconds) : 0
                self?.isPlaying = (self?.player.rate ?? 0) > 0
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.didFinishTrack() }
        }
        configureRemoteCommands()
        refreshQueue()
    }

    func play(_ track: Track) {
        sequenceContext = nil
        sequenceCursor = nil
        startPlayback(track)
    }

    func playFromList(_ track: Track, context: TrackPlaybackContext) {
        sequenceContext = context
        sequenceCursor = track
        startPlayback(track)
    }

    private func startPlayback(_ track: Track) {
        let token = UUID()
        loadToken = token
        Task {
            do {
                let url: URL
                if let cachedURL = try await offlineCache.cachedPlayableURL(for: track) {
                    guard token == loadToken else { return }
                    releaseScope()
                    url = cachedURL
                } else {
                    guard let root = try await Task.detached(priority: .userInitiated, operation: {
                        try self.database.scanRoot(id: track.rootID)
                    }).value else { throw MassiveMusicError.scanRootUnavailable }
                    let scoped = try SecurityScopedRoot.resolve(bookmark: root.bookmark)
                    guard FileManager.default.fileExists(atPath: scoped.url.path) else {
                        throw MassiveMusicError.scanRootUnavailable
                    }
                    guard token == loadToken else { return }
                    releaseScope()
                    activeScopeStarted = scoped.url.startAccessingSecurityScopedResource()
                    activeScopedURL = scoped.url
                    let sourceURL = scoped.url.appending(path: track.relativePath)
                    guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                        throw MassiveMusicError.trackUnavailable
                    }
                    url = try await offlineCache.playableURL(for: track, sourceURL: sourceURL)
                }
                let item = AVPlayerItem(url: url)
                player.replaceCurrentItem(with: item)
                currentTrack = track
                elapsed = 0
                duration = track.duration
                errorMessage = nil
                player.play()
                try? await Task.detached { try self.database.markPlayed(trackID: track.id) }.value
                updateNowPlaying()
            } catch {
                if token == loadToken {
                    errorMessage = error.localizedDescription
                    isPlaying = false
                }
            }
        }
    }

    func togglePlayPause() {
        guard player.currentItem != nil else { return }
        if player.rate > 0 { player.pause() } else { player.play() }
        isPlaying = player.rate > 0
        updateNowPlaying()
    }

    func dismissError() { errorMessage = nil }

    func toggleShuffle() {
        shuffleEnabled.toggle()
        if shuffleEnabled { shuffleSeed = Int64.random(in: 1...Int64.max) }
    }

    func seek(to seconds: Double) {
        let target = CMTime(seconds: max(0, min(duration, seconds)), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func next() {
        Task {
            do {
                let queued = try await Task.detached(priority: .userInitiated) { try self.database.dequeueNext() }.value
                if let queued {
                    refreshQueue()
                    startPlayback(queued)
                } else {
                    loadAdjacent(direction: 1)
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }
    func previous() {
        if elapsed > 3 { seek(to: 0) } else { loadAdjacent(direction: -1) }
    }

    private func loadAdjacent(direction: Int) {
        guard let currentTrack else { return }
        let shouldShuffle = shuffleEnabled
        let seed = shuffleSeed
        let context = sequenceContext
        let cursor = sequenceCursor ?? currentTrack
        Task {
            do {
                let nextTrack = try await Task.detached(priority: .userInitiated) {
                    if direction > 0, shouldShuffle {
                        return try self.database.shuffleCandidates(
                            afterID: currentTrack.id,
                            seed: seed,
                            limit: 1
                        ).first ?? self.database.adjacentTrack(to: currentTrack.id, direction: direction)
                    }
                    if let context {
                        return try self.database.adjacentTrack(in: context, from: cursor, direction: direction)
                    }
                    return try self.database.adjacentTrack(to: currentTrack.id, direction: direction)
                }.value
                if let nextTrack {
                    if context != nil { sequenceCursor = nextTrack }
                    startPlayback(nextTrack)
                }
                else if repeatMode == .all { seek(to: 0); player.play() }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func didFinishTrack() {
        if repeatMode == .one {
            seek(to: 0)
            player.play()
        } else {
            next()
        }
    }

    func addToUpNext(_ track: Track) {
        Task {
            do {
                _ = try await Task.detached { try self.database.enqueueNext(trackID: track.id) }.value
                refreshQueue()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func playQueued(_ track: Track) {
        Task {
            do {
                try await Task.detached { try self.database.removeFromPlayQueue(trackID: track.id) }.value
                refreshQueue()
                startPlayback(track)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func removeFromUpNext(_ track: Track) {
        Task {
            do {
                try await Task.detached { try self.database.removeFromPlayQueue(trackID: track.id) }.value
                refreshQueue()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func clearUpNext() {
        Task {
            do {
                try await Task.detached { try self.database.clearPlayQueue() }.value
                queueOffset = 0
                refreshQueue()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    var queuePageNumber: Int { queueTotalCount == 0 ? 0 : queueOffset / queuePageSize + 1 }
    var queuePageCount: Int { queueTotalCount == 0 ? 0 : Int(ceil(Double(queueTotalCount) / Double(queuePageSize))) }
    var canGoToPreviousQueuePage: Bool { queueOffset > 0 }
    var canGoToNextQueuePage: Bool { queueOffset + upNextTracks.count < queueTotalCount }

    func previousQueuePage() {
        queueOffset = max(0, queueOffset - queuePageSize)
        refreshQueue()
    }

    func nextQueuePage() {
        guard canGoToNextQueuePage else { return }
        queueOffset += queuePageSize
        refreshQueue()
    }

    func refreshQueue() {
        let requestedOffset = queueOffset
        Task {
            do {
                let page = try await Task.detached {
                    try self.database.playQueuePage(offset: requestedOffset, limit: self.queuePageSize)
                }.value
                if page.totalCount > 0, requestedOffset >= page.totalCount {
                    queueOffset = max(0, ((page.totalCount - 1) / queuePageSize) * queuePageSize)
                    refreshQueue()
                    return
                }
                upNextTracks = page.tracks
                queueTotalCount = page.totalCount
                queueOffset = page.offset
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func releaseScope() {
        if activeScopeStarted { activeScopedURL?.stopAccessingSecurityScopedResource() }
        activeScopeStarted = false
        activeScopedURL = nil
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player.pause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let track = currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: player.rate
        ]
    }
}
