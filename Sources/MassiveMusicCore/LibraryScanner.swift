import Foundation

public actor LibraryScanner {
    public typealias ProgressHandler = @Sendable (ScanProgress) -> Void

    private let database: LibraryDatabase
    private var isPaused = false
    private var shouldCancel = false
    private var activeSessionID: Int64?

    public init(database: LibraryDatabase) {
        self.database = database
    }

    public func pause() { isPaused = true }
    public func resume() { isPaused = false }
    public func cancel() { shouldCancel = true }

    public func scan(
        root: SecurityScopedRoot,
        rootID: Int64,
        progress handler: ProgressHandler? = nil
    ) async throws {
        shouldCancel = false
        isPaused = false
        let rootURL = root.url
        let didStart = rootURL.startAccessingSecurityScopedResource()
        defer { if didStart { rootURL.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            try database.setRootAvailability(id: rootID, isAvailable: false)
            throw MassiveMusicError.scanRootUnavailable
        }
        // A rescan can be initiated from view state that predates a scan-root
        // refresh. Never insert a foreign-keyed session with that stale ID:
        // resolve the selected folder against the current database first.
        let normalizedPath = rootURL.path.precomposedStringWithCanonicalMapping
        let registeredRoot = try database.scanRoot(id: rootID)
        let effectiveRootID: Int64
        if registeredRoot?.lastKnownPath.precomposedStringWithCanonicalMapping == normalizedPath {
            effectiveRootID = rootID
        } else {
            let values = try rootURL.resourceValues(forKeys: [.volumeUUIDStringKey, .nameKey])
            effectiveRootID = try database.addScanRoot(
                displayName: values.name ?? rootURL.lastPathComponent,
                bookmark: root.bookmark,
                volumeUUID: values.volumeUUIDString,
                path: normalizedPath
            )
        }
        try database.setRootAvailability(id: effectiveRootID, isAvailable: true, path: normalizedPath)
        let resumable = try database.resumableSession(rootID: effectiveRootID)
        let sessionID: Int64
        if let existingID = resumable?.id {
            sessionID = existingID
        } else {
            sessionID = try database.createScanSession(rootID: effectiveRootID)
        }
        activeSessionID = sessionID
        defer { activeSessionID = nil }
        try await performScan(
            rootURL: rootURL,
            rootID: effectiveRootID,
            sessionID: sessionID,
            resumeCursor: resumable?.cursor,
            progress: handler
        )
    }

    private func performScan(
        rootURL: URL,
        rootID: Int64,
        sessionID: Int64,
        resumeCursor: String?,
        progress handler: ProgressHandler?
    ) async throws {
        let start = ContinuousClock.now
        var discovered = 0
        var processed = 0
        var changed = 0
        var skipped = 0
        var errors = 0
        var currentPath = resumeCursor ?? ""
        var imports: [TrackImport] = []
        var unchangedKeys: [String] = []
        imports.reserveCapacity(LibraryDatabase.scanCommitSize)
        unchangedKeys.reserveCapacity(LibraryDatabase.scanCommitSize)

        // Re-enumerate from the root after a restart. Files committed before the
        // persisted cursor are signature-checked and skipped cheaply. This is
        // safer than relying on FileManager's enumeration order remaining stable.

        let keys: [URLResourceKey] = [
            .isRegularFileKey, .fileSizeKey, .contentModificationDateKey,
            .fileResourceIdentifierKey, .volumeUUIDStringKey, .isReadableKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { throw MassiveMusicError.scanRootUnavailable }

        while let fileURL = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            if shouldCancel {
                try flush(
                    imports: &imports, unchangedKeys: &unchangedKeys, sessionID: sessionID,
                    changed: &changed
                )
                try database.updateScanSession(
                    id: sessionID, state: .cancelled, cursor: currentPath,
                    discovered: discovered, processed: processed, changed: changed,
                    skipped: skipped, errors: errors
                )
                handler?(makeProgress(
                    sessionID: sessionID, state: .cancelled, discovered: discovered,
                    processed: processed, changed: changed, skipped: skipped, errors: errors,
                    start: start, path: currentPath
                ))
                return
            }
            while isPaused {
                try database.updateScanSession(
                    id: sessionID, state: .paused, cursor: currentPath,
                    discovered: discovered, processed: processed, changed: changed,
                    skipped: skipped, errors: errors
                )
                handler?(makeProgress(
                    sessionID: sessionID, state: .paused, discovered: discovered,
                    processed: processed, changed: changed, skipped: skipped, errors: errors,
                    start: start, path: currentPath
                ))
                try await Task.sleep(for: .milliseconds(200))
                try Task.checkCancellation()
            }

            let ext = fileURL.pathExtension.lowercased()
            guard ["mp3", "m4a", "wav", "flac"].contains(ext) else { continue }
            var relativePath = String(fileURL.path.dropFirst(rootURL.path.count))
            if relativePath.hasPrefix("/") { relativePath.removeFirst() }
            discovered += 1
            currentPath = relativePath

            do {
                let values = try fileURL.resourceValues(forKeys: Set(keys))
                guard values.isRegularFile == true, values.isReadable != false else {
                    throw CocoaError(.fileReadNoPermission)
                }
                let fileSize = Int64(values.fileSize ?? 0)
                let modifiedAt = values.contentModificationDate ?? .distantPast
                let resourceID = values.fileResourceIdentifier.map { String(describing: $0) }
                let volumeUUID = values.volumeUUIDString ?? "unknown-volume"
                let identityKey = Self.identityKey(
                    volumeUUID: volumeUUID,
                    resourceID: resourceID,
                    relativePath: relativePath
                )

                if try database.isExcluded(identityKey: identityKey) {
                    unchangedKeys.append(identityKey)
                    skipped += 1
                } else if let signature = try database.signature(identityKey: identityKey),
                   signature.size == fileSize,
                   abs(signature.modifiedAt.timeIntervalSince(modifiedAt)) < 0.001 {
                    unchangedKeys.append(identityKey)
                    skipped += 1
                } else {
                    let metadata = await AudioMetadataReader.read(url: fileURL)
                    let track = Track(
                        rootID: rootID,
                        relativePath: relativePath,
                        filename: fileURL.lastPathComponent,
                        title: metadata.title,
                        artist: metadata.artist,
                        album: metadata.album,
                        albumArtist: metadata.albumArtist,
                        genre: metadata.genre,
                        isCompilation: metadata.isCompilation,
                        discNumber: metadata.discNumber,
                        trackNumber: metadata.trackNumber,
                        duration: metadata.duration,
                        fileSize: fileSize,
                        modifiedAt: modifiedAt,
                        format: ext,
                        bitrate: metadata.bitrate,
                        hasArtwork: metadata.hasArtwork
                    )
                    imports.append(TrackImport(identityKey: identityKey, fileResourceID: resourceID, track: track))
                }
                processed += 1
            } catch {
                errors += 1
                processed += 1
                try database.recordScanError(sessionID: sessionID, path: relativePath, message: error.localizedDescription)
            }

            if imports.count + unchangedKeys.count >= LibraryDatabase.scanCommitSize {
                try flush(
                    imports: &imports, unchangedKeys: &unchangedKeys, sessionID: sessionID,
                    changed: &changed
                )
                try database.updateScanSession(
                    id: sessionID, state: .running, cursor: currentPath,
                    discovered: discovered, processed: processed, changed: changed,
                    skipped: skipped, errors: errors
                )
                handler?(makeProgress(
                    sessionID: sessionID, state: .running, discovered: discovered,
                    processed: processed, changed: changed, skipped: skipped, errors: errors,
                    start: start, path: currentPath
                ))
            }
        }

        try flush(imports: &imports, unchangedKeys: &unchangedKeys, sessionID: sessionID, changed: &changed)
        _ = try database.markMissingTracks(rootID: rootID, sessionID: sessionID)
        try database.updateScanSession(
            id: sessionID, state: .completed, cursor: nil,
            discovered: discovered, processed: processed, changed: changed,
            skipped: skipped, errors: errors, finished: true
        )
        handler?(makeProgress(
            sessionID: sessionID, state: .completed, discovered: discovered,
            processed: processed, changed: changed, skipped: skipped, errors: errors,
            start: start, path: currentPath
        ))
    }

    private func flush(
        imports: inout [TrackImport],
        unchangedKeys: inout [String],
        sessionID: Int64,
        changed: inout Int
    ) throws {
        changed += try database.commitScanBatch(
            imports: imports,
            unchangedIdentityKeys: unchangedKeys,
            sessionID: sessionID
        )
        imports.removeAll(keepingCapacity: true)
        unchangedKeys.removeAll(keepingCapacity: true)
    }

    private func makeProgress(
        sessionID: Int64,
        state: ScanState,
        discovered: Int,
        processed: Int,
        changed: Int,
        skipped: Int,
        errors: Int,
        start: ContinuousClock.Instant,
        path: String
    ) -> ScanProgress {
        let duration = start.duration(to: .now).components
        let seconds = max(0.001, Double(duration.seconds) + Double(duration.attoseconds) / 1e18)
        return ScanProgress(
            sessionID: sessionID, state: state, discovered: discovered, processed: processed,
            insertedOrUpdated: changed, skipped: skipped, errors: errors,
            tracksPerSecond: Double(processed) / seconds, currentPath: path
        )
    }

    private static func identityKey(
        volumeUUID: String,
        resourceID: String?,
        relativePath: String
    ) -> String {
        if let resourceID, !resourceID.isEmpty { return "\(volumeUUID)|resource|\(resourceID)" }
        return "\(volumeUUID)|path|\(relativePath)"
    }
}
