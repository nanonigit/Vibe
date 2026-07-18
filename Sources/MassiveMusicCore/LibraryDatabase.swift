import Foundation
import GRDB

public final class LibraryDatabase: @unchecked Sendable {
    public static let defaultPageSize = 200
    public static let scanCommitSize = 750
    public static let playlistCommitSize = 1_000

    private let pool: DatabasePool
    public let databaseURL: URL

    public init(url: URL) throws {
        databaseURL = url
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var configuration = Configuration()
        configuration.maximumReaderCount = 6
        configuration.busyMode = .timeout(5)
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "PRAGMA cache_size = -32768")
            try db.execute(sql: "PRAGMA temp_store = MEMORY")
        }
        pool = try DatabasePool(path: url.path, configuration: configuration)
        try pool.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }
        try Self.makeMigrator().migrate(pool)
    }

    public static func applicationSupportURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appending(path: "MassiveMusic", directoryHint: .isDirectory)
            .appending(path: "MassiveMusic.sqlite")
    }

    private static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_initial") { db in
            try db.execute(sql: Schema.initial)
            try db.execute(
                sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                arguments: [1, Date().timeIntervalSince1970]
            )
        }
        migrator.registerMigration("v2_library_experience") { db in
            try db.execute(sql: Schema.libraryExperience)
            try db.execute(
                sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                arguments: [2, Date().timeIntervalSince1970]
            )
        }
        migrator.registerMigration("v3_track_editing_and_exclusions") { db in
            try db.execute(sql: Schema.trackEditingAndExclusions)
            try db.execute(
                sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                arguments: [3, Date().timeIntervalSince1970]
            )
        }
        migrator.registerMigration("v4_metadata_diagnostics") { db in
            try db.execute(sql: Schema.metadataDiagnostics)
            try db.execute(
                sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                arguments: [4, Date().timeIntervalSince1970]
            )
        }
        migrator.registerMigration("v5_play_queue") { db in
            try db.execute(sql: Schema.playQueue)
            try db.execute(
                sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                arguments: [5, Date().timeIntervalSince1970]
            )
        }
        migrator.registerMigration("v6_pinned_offline_cache") { db in
            try db.execute(sql: Schema.pinnedOfflineCache)
            try db.execute(
                sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                arguments: [6, Date().timeIntervalSince1970]
            )
        }
        migrator.registerMigration("v7_library_activity_log") { db in
            try db.execute(sql: Schema.libraryActivityLog)
            try db.execute(
                sql: "INSERT INTO schema_migrations(version, applied_at) VALUES (?, ?)",
                arguments: [7, Date().timeIntervalSince1970]
            )
        }
        return migrator
    }

    public func journalMode() throws -> String {
        try pool.read { db in
            try String.fetchOne(db, sql: "PRAGMA journal_mode") ?? ""
        }
    }

    public func schemaVersion() throws -> Int {
        try pool.read { db in
            try Int.fetchOne(db, sql: "SELECT MAX(version) FROM schema_migrations") ?? 0
        }
    }

    public func trackCount(availableOnly: Bool = false) throws -> Int {
        try pool.read { db in
            let suffix = availableOnly ? " WHERE is_available = 1" : ""
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tracks\(suffix)") ?? 0
        }
    }

    public func unavailableTrackCount() throws -> Int {
        try pool.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tracks WHERE is_available = 0") ?? 0 }
    }

    public func activityLogPage(
        kinds: Set<LibraryActivityKind> = [],
        query: String = "",
        offset: Int = 0,
        limit: Int = defaultPageSize
    ) throws -> LibraryActivityPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let safeOffset = max(0, offset)
        return try pool.read { db in
            var predicates: [String] = []
            var arguments: StatementArguments = []
            if !kinds.isEmpty {
                let orderedKinds = kinds.sorted { $0.rawValue < $1.rawValue }
                predicates.append("kind IN (\(Array(repeating: "?", count: orderedKinds.count).joined(separator: ",")))")
                arguments += StatementArguments(orderedKinds.map(\.rawValue))
            }
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedQuery.isEmpty {
                predicates.append("(filename LIKE ? ESCAPE '\\' OR title LIKE ? ESCAPE '\\' OR artist LIKE ? ESCAPE '\\' OR album LIKE ? ESCAPE '\\' OR relative_path LIKE ? ESCAPE '\\' OR absolute_path LIKE ? ESCAPE '\\')")
                let escaped = trimmedQuery
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                let pattern = "%\(escaped)%"
                arguments += [pattern, pattern, pattern, pattern, pattern, pattern]
            }
            let whereSQL = predicates.isEmpty ? "" : " WHERE " + predicates.joined(separator: " AND ")
            let total = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM library_activity_log\(whereSQL)", arguments: arguments
            ) ?? 0
            var pageArguments = arguments
            pageArguments += [limit, safeOffset]
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM library_activity_log\(whereSQL) ORDER BY occurred_at DESC, id DESC LIMIT ? OFFSET ?",
                arguments: pageArguments
            )
            return LibraryActivityPage(
                events: rows.map(Self.decodeActivityEvent), offset: safeOffset,
                limit: limit, totalCount: total
            )
        }
    }

    public func track(id: Int64) throws -> Track? {
        try pool.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM tracks WHERE id = ?", arguments: [id]) else {
                return nil
            }
            return Self.decodeTrack(row)
        }
    }

    /// Returns a bounded keyset page so maintenance never materializes the
    /// entire library and remains stable while each repaired title is updated.
    public func tracksWithLeadingTitleSpaces(afterID: Int64, limit: Int = defaultPageSize) throws -> [Track] {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        return try pool.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM tracks
                    WHERE id > ? AND is_available = 1
                      AND substr(title, 1, 1) IN (' ', '　')
                    ORDER BY id LIMIT ?
                    """,
                arguments: [afterID, limit]
            )
            return rows.map(Self.decodeTrack)
        }
    }

    public func isExcluded(identityKey: String) throws -> Bool {
        try pool.read { db in
            try Bool.fetchOne(
                db, sql: "SELECT EXISTS(SELECT 1 FROM excluded_tracks WHERE identity_key = ?)",
                arguments: [identityKey]
            ) ?? false
        }
    }

    @discardableResult
    public func removeTrackFromLibrary(id: Int64, fileWasTrashed: Bool) throws -> Bool {
        try pool.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM tracks WHERE id = ?",
                arguments: [id]
            ) else { return false }
            try Self.insertActivity(
                db: db, kind: fileWasTrashed ? .movedToTrash : .removedFromLibrary,
                trackRow: row, changes: []
            )
            try db.execute(
                sql: """
                    INSERT INTO excluded_tracks(identity_key, root_id, relative_path, removed_at, file_was_trashed)
                    VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(identity_key) DO UPDATE SET removed_at = excluded.removed_at,
                        file_was_trashed = excluded.file_was_trashed
                    """,
                arguments: [row["identity_key"], row["root_id"], row["relative_path"], Date().timeIntervalSince1970, fileWasTrashed]
            )
            try db.execute(sql: "DELETE FROM tracks WHERE id = ?", arguments: [id])
            let removed = db.changesCount > 0
            try Self.pruneActivityLog(db: db)
            return removed
        }
    }

    public func updateTrackMetadata(
        id: Int64,
        edit: TrackMetadataEdit,
        fileSize: Int64,
        modifiedAt: Date
    ) throws {
        try pool.write { db in
            let previous = try Row.fetchOne(db, sql: "SELECT * FROM tracks WHERE id = ?", arguments: [id])
            try db.execute(
                sql: """
                    UPDATE tracks SET title = ?, artist = ?, album = ?, album_artist = ?, genre = ?,
                        disc_number = ?, track_number = ?, file_size = ?, modified_at = ?,
                        has_artwork = CASE WHEN ? THEN 1 ELSE has_artwork END
                    WHERE id = ?
                    """,
                arguments: [edit.title, edit.artist, edit.album, edit.albumArtist, edit.genre,
                            edit.discNumber, edit.trackNumber, fileSize, modifiedAt.timeIntervalSince1970,
                            edit.artworkData != nil, id]
            )
            if let updated = try Row.fetchOne(db, sql: "SELECT * FROM tracks WHERE id = ?", arguments: [id]) {
                let changes = Self.activityChanges(from: previous, to: updated)
                if !changes.isEmpty {
                    try Self.insertActivity(db: db, kind: .metadataChanged, trackRow: updated, changes: changes)
                    try Self.pruneActivityLog(db: db)
                }
            }
        }
    }

    public func pageTracks(
        query: String = "",
        sort: TrackSort = .title,
        direction: SortDirection = .ascending,
        offset: Int = 0,
        limit: Int = defaultPageSize,
        availableOnly: Bool = false
    ) throws -> TrackPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let safeOffset = max(0, offset)
        let searchPattern = Self.ftsPattern(query)

        return try pool.read { db in
            var whereParts: [String] = []
            var arguments: StatementArguments = []
            var from = "tracks t"
            if let searchPattern {
                from += " JOIN tracks_fts f ON f.rowid = t.id"
                whereParts.append("tracks_fts MATCH ?")
                arguments += [searchPattern]
            }
            if availableOnly { whereParts.append("t.is_available = 1") }
            let whereSQL = whereParts.isEmpty ? "" : " WHERE " + whereParts.joined(separator: " AND ")
            let total = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM \(from)\(whereSQL)",
                arguments: arguments
            ) ?? 0
            let orderSQL = Self.orderSQL(sort, direction: direction)
            var pageArguments = arguments
            pageArguments += [limit, safeOffset]
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT t.* FROM \(from)\(whereSQL) ORDER BY \(orderSQL) LIMIT ? OFFSET ?",
                arguments: pageArguments
            )
            return TrackPage(
                tracks: rows.map(Self.decodeTrack),
                offset: safeOffset,
                limit: limit,
                totalCount: total
            )
        }
    }

    @discardableResult
    public func enqueueNext(trackID: Int64) throws -> Bool {
        try pool.write { db in
            guard try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM tracks WHERE id = ? AND is_available = 1)", arguments: [trackID]) == true else {
                return false
            }
            let nextPosition = (try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(position), -1) + 1 FROM play_queue")) ?? 0
            try db.execute(
                sql: "INSERT INTO play_queue(track_id, position, added_at) VALUES (?, ?, ?)",
                arguments: [trackID, nextPosition, Date().timeIntervalSince1970]
            )
            return true
        }
    }

    public func playQueuePage(offset: Int = 0, limit: Int = defaultPageSize) throws -> TrackPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let safeOffset = max(0, offset)
        return try pool.read { db in
            let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM play_queue") ?? 0
            let rows = try Row.fetchAll(db, sql: """
                SELECT t.* FROM play_queue q JOIN tracks t ON t.id = q.track_id
                ORDER BY q.position, q.id LIMIT ? OFFSET ?
                """, arguments: [limit, safeOffset])
            return TrackPage(tracks: rows.map(Self.decodeTrack), offset: safeOffset, limit: limit, totalCount: total)
        }
    }

    public func dequeueNext() throws -> Track? {
        try pool.write { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT q.id AS queue_id, t.* FROM play_queue q JOIN tracks t ON t.id = q.track_id
                WHERE t.is_available = 1 ORDER BY q.position, q.id LIMIT 1
                """) else {
                try db.execute(sql: "DELETE FROM play_queue WHERE track_id NOT IN (SELECT id FROM tracks WHERE is_available = 1)")
                return nil
            }
            let queueID: Int64 = row["queue_id"]
            try db.execute(sql: "DELETE FROM play_queue WHERE id = ?", arguments: [queueID])
            return Self.decodeTrack(row)
        }
    }

    public func removeFromPlayQueue(trackID: Int64) throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM play_queue WHERE id = (SELECT id FROM play_queue WHERE track_id = ? ORDER BY position, id LIMIT 1)", arguments: [trackID])
        }
    }

    public func clearPlayQueue() throws {
        try pool.write { db in try db.execute(sql: "DELETE FROM play_queue") }
    }

    public func metadataIssueSummaries() throws -> [MetadataIssueSummary] {
        try pool.read { db in
            try [MetadataIssueKind.missingTitle, .missingArtist, .missingAlbum, .urlInMP3Metadata, .duplicateTracks].map { kind in
                MetadataIssueSummary(
                    kind: kind,
                    count: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tracks t WHERE \(Self.metadataIssuePredicate(kind))") ?? 0
                )
            }
        }
    }

    public func pageMetadataIssues(
        kind: MetadataIssueKind,
        sort: TrackSort = .title,
        direction: SortDirection = .ascending,
        offset: Int = 0,
        limit: Int = defaultPageSize
    ) throws -> TrackPage {
        guard kind != .suspectedVariations else { throw MassiveMusicError.invalidPageSize }
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let safeOffset = max(0, offset)
        let predicate = Self.metadataIssuePredicate(kind)
        return try pool.read { db in
            let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tracks t WHERE \(predicate)") ?? 0
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT t.* FROM tracks t WHERE \(predicate) ORDER BY \(Self.orderSQL(sort, direction: direction)) LIMIT ? OFFSET ?",
                arguments: [limit, safeOffset]
            )
            return TrackPage(tracks: rows.map(Self.decodeTrack), offset: safeOffset, limit: limit, totalCount: total)
        }
    }

    public func resetPendingMetadataAnalysis() throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM metadata_terms")
            try db.execute(sql: "DELETE FROM metadata_variation_candidates WHERE status = 'pending'")
        }
    }

    public func distinctMetadataTerms(
        field: MetadataField,
        after value: String?,
        limit: Int = 1_000
    ) throws -> [(value: String, count: Int)] {
        let column = Self.metadataColumn(field)
        return try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT \(column) AS value, COUNT(*) AS track_count
                FROM tracks
                WHERE trim(\(column)) <> '' AND (? IS NULL OR \(column) > ? COLLATE BINARY)
                GROUP BY \(column) COLLATE BINARY
                ORDER BY \(column) COLLATE BINARY
                LIMIT ?
                """, arguments: [value, value, limit])
            return rows.map { ($0["value"], $0["track_count"]) }
        }
    }

    public func insertMetadataTerms(
        field: MetadataField,
        terms: [(value: String, normalized: String, prefix: String, count: Int)]
    ) throws {
        guard !terms.isEmpty else { return }
        try pool.write { db in
            for term in terms {
                try db.execute(sql: """
                    INSERT OR REPLACE INTO metadata_terms(field, value, normalized, prefix, char_count, track_count)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """, arguments: [field.rawValue, term.value, term.normalized, term.prefix,
                                      term.normalized.count, term.count])
            }
        }
    }

    public func generateNormalizationCandidates() throws -> Int {
        try pool.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO metadata_variation_candidates(
                    field, value_a, value_b, track_count_a, track_count_b, reason, edit_distance, status, created_at
                )
                SELECT a.field, a.value, b.value, a.track_count, b.track_count,
                       'normalization', 0, 'pending', ?
                FROM metadata_terms a
                JOIN metadata_terms b ON b.field = a.field AND b.normalized = a.normalized AND b.id > a.id
                WHERE a.normalized <> ''
                  AND a.id = (SELECT MIN(c.id) FROM metadata_terms c WHERE c.field = a.field AND c.normalized = a.normalized)
                """, arguments: [Date().timeIntervalSince1970])
            return db.changesCount
        }
    }

    public func metadataPrefixes(field: MetadataField, after prefix: String?, limit: Int = 500) throws -> [String] {
        try pool.read { db in
            try String.fetchAll(db, sql: """
                SELECT prefix FROM metadata_terms
                WHERE field = ? AND prefix <> '' AND (? IS NULL OR prefix > ? COLLATE BINARY)
                GROUP BY prefix COLLATE BINARY ORDER BY prefix COLLATE BINARY LIMIT ?
                """, arguments: [field.rawValue, prefix, prefix, limit])
        }
    }

    public func metadataTerms(field: MetadataField, prefix: String, limit: Int = 201) throws -> [MetadataTerm] {
        try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT value, normalized, track_count FROM metadata_terms
                WHERE field = ? AND prefix = ? COLLATE BINARY AND char_count BETWEEN 4 AND 80
                ORDER BY normalized COLLATE BINARY LIMIT ?
                """, arguments: [field.rawValue, prefix, limit]).map {
                    MetadataTerm(value: $0["value"], normalized: $0["normalized"], trackCount: $0["track_count"])
                }
        }
    }

    public func storedMetadataTerms(
        field: MetadataField,
        afterPrefix: String?,
        afterID: Int64?,
        limit: Int = 1_000
    ) throws -> [StoredMetadataTerm] {
        try pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT id, prefix, value, normalized, track_count FROM metadata_terms
                WHERE field = ? AND prefix <> '' AND char_count BETWEEN 4 AND 80
                  AND (? IS NULL OR prefix > ? COLLATE BINARY OR (prefix = ? COLLATE BINARY AND id > ?))
                ORDER BY prefix COLLATE BINARY, id LIMIT ?
                """, arguments: [field.rawValue, afterPrefix, afterPrefix, afterPrefix, afterID, limit]).map {
                    StoredMetadataTerm(
                        id: $0["id"], prefix: $0["prefix"],
                        term: MetadataTerm(value: $0["value"], normalized: $0["normalized"], trackCount: $0["track_count"])
                    )
                }
        }
    }

    @discardableResult
    public func insertTypoCandidate(
        field: MetadataField,
        first: MetadataTerm,
        second: MetadataTerm,
        distance: Int
    ) throws -> Bool {
        let ordered = first.value < second.value ? (first, second) : (second, first)
        return try pool.write { db in
            try db.execute(sql: """
                INSERT OR IGNORE INTO metadata_variation_candidates(
                    field, value_a, value_b, track_count_a, track_count_b, reason, edit_distance, status, created_at
                ) VALUES (?, ?, ?, ?, ?, 'likelyTypo', ?, 'pending', ?)
                """, arguments: [field.rawValue, ordered.0.value, ordered.1.value,
                                  ordered.0.trackCount, ordered.1.trackCount, distance, Date().timeIntervalSince1970])
            return db.changesCount > 0
        }
    }

    public func metadataVariationCount() throws -> Int {
        try pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM metadata_variation_candidates WHERE status = 'pending'") ?? 0
        }
    }

    public func pageMetadataVariations(offset: Int = 0, limit: Int = defaultPageSize) throws -> MetadataVariationPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let safeOffset = max(0, offset)
        return try pool.read { db in
            let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM metadata_variation_candidates WHERE status = 'pending'") ?? 0
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM metadata_variation_candidates WHERE status = 'pending'
                ORDER BY CASE reason WHEN 'normalization' THEN 0 ELSE 1 END, field, value_a COLLATE NOCASE
                LIMIT ? OFFSET ?
                """, arguments: [limit, safeOffset])
            let candidates = rows.compactMap { row -> MetadataVariationCandidate? in
                guard let field = MetadataField(rawValue: row["field"]),
                      let reason = MetadataVariationReason(rawValue: row["reason"]) else { return nil }
                return MetadataVariationCandidate(
                    id: row["id"], field: field, valueA: row["value_a"], valueB: row["value_b"],
                    trackCountA: row["track_count_a"], trackCountB: row["track_count_b"],
                    reason: reason, editDistance: row["edit_distance"]
                )
            }
            return MetadataVariationPage(candidates: candidates, offset: safeOffset, limit: limit, totalCount: total)
        }
    }

    public func ignoreMetadataVariation(id: Int64) throws {
        try pool.write { db in
            try db.execute(sql: "UPDATE metadata_variation_candidates SET status = 'ignored' WHERE id = ?", arguments: [id])
        }
    }

    public func pageFavoriteTracks(
        sort: TrackSort = .title,
        direction: SortDirection = .ascending,
        offset: Int = 0,
        limit: Int = defaultPageSize
    ) throws -> TrackPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        return try pool.read { db in
            let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tracks WHERE is_favorite = 1") ?? 0
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT t.* FROM tracks t WHERE is_favorite = 1 ORDER BY \(Self.orderSQL(sort, direction: direction)) LIMIT ? OFFSET ?",
                arguments: [limit, max(0, offset)]
            )
            return TrackPage(tracks: rows.map(Self.decodeTrack), offset: max(0, offset), limit: limit, totalCount: total)
        }
    }

    @discardableResult
    public func toggleFavorite(trackID: Int64) throws -> Bool {
        try pool.write { db in
            try db.execute(sql: "UPDATE tracks SET is_favorite = CASE is_favorite WHEN 1 THEN 0 ELSE 1 END WHERE id = ?", arguments: [trackID])
            return (try Bool.fetchOne(db, sql: "SELECT is_favorite FROM tracks WHERE id = ?", arguments: [trackID])) ?? false
        }
    }

    public func setFavorite(trackID: Int64, isFavorite: Bool) throws {
        try pool.write { db in
            try db.execute(
                sql: "UPDATE tracks SET is_favorite = ? WHERE id = ?",
                arguments: [isFavorite, trackID]
            )
        }
    }

    public func markPlayed(trackID: Int64) throws {
        try pool.write { db in
            try db.execute(sql: "UPDATE tracks SET play_count = play_count + 1, last_played_at = ? WHERE id = ?", arguments: [Date().timeIntervalSince1970, trackID])
        }
    }

    public func similarTracks(to track: Track, limit: Int = 12) throws -> [Track] {
        guard (1...100).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        return try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT * FROM tracks
                WHERE id <> ? AND is_available = 1
                  AND ((? <> '' AND genre = ?) OR (? <> '' AND artist = ?) OR (? <> '' AND album_artist = ?))
                ORDER BY CASE WHEN genre = ? THEN 0 WHEN artist = ? THEN 1 ELSE 2 END,
                         play_count DESC, id
                LIMIT ?
                """, arguments: [track.id, track.genre, track.genre, track.artist, track.artist,
                                  track.albumArtist, track.albumArtist, track.genre, track.artist, limit])
            return rows.map(Self.decodeTrack)
        }
    }

    public func setSetting(_ value: String, forKey key: String) throws {
        try pool.write { db in
            try db.execute(sql: "INSERT INTO app_settings(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value", arguments: [key, value])
        }
    }

    public func setting(forKey key: String) throws -> String? {
        try pool.read { db in try String.fetchOne(db, sql: "SELECT value FROM app_settings WHERE key = ?", arguments: [key]) }
    }

    public func addStorageDestination(name: String, path: String, bookmark: Data, makePrimary: Bool = true) throws -> Int64 {
        try pool.write { db in
            if makePrimary { try db.execute(sql: "UPDATE storage_destinations SET is_primary = 0") }
            try db.execute(sql: """
                INSERT INTO storage_destinations(name, path, bookmark, is_primary, is_available, created_at)
                VALUES (?, ?, ?, ?, 1, ?)
                ON CONFLICT(path) DO UPDATE SET name = excluded.name, bookmark = excluded.bookmark,
                    is_primary = excluded.is_primary, is_available = 1
                """, arguments: [name, path, bookmark, makePrimary, Date().timeIntervalSince1970])
            return try Int64.fetchOne(db, sql: "SELECT id FROM storage_destinations WHERE path = ?", arguments: [path]) ?? 0
        }
    }
    public func renameVibeStorageDestinationToMain() throws {
        try pool.write { db in
            try db.execute(sql: "UPDATE storage_destinations SET name = 'メイン保管先' WHERE name = 'Vibe'")
            try db.execute(sql: "UPDATE scan_roots SET display_name = 'メイン保管先' WHERE display_name = 'Vibe'")
            try db.execute(sql: "DELETE FROM tracks WHERE id NOT IN (SELECT MIN(id) FROM tracks GROUP BY identity_key)")
        }
    }

    public func storageDestinations() throws -> [StorageDestination] {
        try pool.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM storage_destinations ORDER BY is_primary DESC, name COLLATE NOCASE").map {
                StorageDestination(id: $0["id"], name: $0["name"], path: $0["path"], bookmark: $0["bookmark"], isPrimary: $0["is_primary"], isAvailable: $0["is_available"])
            }
        }
    }

    public func addPendingImport(localPath: String, filename: String) throws -> Int64 {
        try pool.write { db in
            try db.execute(sql: "INSERT INTO pending_imports(local_path, filename, state, created_at) VALUES (?, ?, 'staged', ?)", arguments: [localPath, filename, Date().timeIntervalSince1970])
            return db.lastInsertedRowID
        }
    }

    public func pendingImports() throws -> [PendingImport] {
        try pool.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM pending_imports ORDER BY created_at DESC LIMIT 1000").compactMap { row in
                guard let state = ImportState(rawValue: row["state"]) else { return nil }
                return PendingImport(id: row["id"], localPath: row["local_path"], filename: row["filename"], state: state, createdAt: Date(timeIntervalSince1970: row["created_at"]), errorMessage: row["error_message"])
            }
        }
    }
    public func pendingImport(id: Int64) throws -> PendingImport? {
        try pool.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM pending_imports WHERE id = ?", arguments: [id]) else { return nil }
            guard let state = ImportState(rawValue: row["state"]) else { return nil }
            return PendingImport(id: row["id"], localPath: row["local_path"], filename: row["filename"], state: state, createdAt: Date(timeIntervalSince1970: row["created_at"]), errorMessage: row["error_message"])
        }
    }
    public func trackID(forIdentityKey identityKey: String) throws -> Int64? {
        try pool.read { db in
            try Int64.fetchOne(db, sql: "SELECT id FROM tracks WHERE identity_key = ?", arguments: [identityKey])
        }
    }

    public func updatePendingImport(id: Int64, state: ImportState, localPath: String? = nil, error: String? = nil) throws {
        try pool.write { db in
            try db.execute(sql: "UPDATE pending_imports SET state = ?, local_path = COALESCE(?, local_path), error_message = ? WHERE id = ?", arguments: [state.rawValue, localPath, error, id])
        }
    }

    public func cachedLyrics(trackID: Int64) throws -> CachedLyrics? {
        try pool.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM lyrics WHERE track_id = ?", arguments: [trackID]) else { return nil }
            return CachedLyrics(trackID: trackID, provider: row["provider"], plainLyrics: row["plain_lyrics"], syncedLyrics: row["synced_lyrics"], updatedAt: Date(timeIntervalSince1970: row["updated_at"]))
        }
    }

    public func saveLyrics(trackID: Int64, provider: String, plain: String, synced: String?) throws {
        try pool.write { db in
            try db.execute(sql: """
                INSERT INTO lyrics(track_id, provider, plain_lyrics, synced_lyrics, updated_at)
                VALUES (?, ?, ?, ?, ?)
                ON CONFLICT(track_id) DO UPDATE SET provider = excluded.provider, plain_lyrics = excluded.plain_lyrics,
                    synced_lyrics = excluded.synced_lyrics, updated_at = excluded.updated_at
                """, arguments: [trackID, provider, plain, synced, Date().timeIntervalSince1970])
        }
    }

    public func cachedPath(trackID: Int64) throws -> String? {
        try pool.read { db in try String.fetchOne(db, sql: "SELECT local_path FROM local_cache WHERE track_id = ?", arguments: [trackID]) }
    }

    public func cachedTrackIDs(in trackIDs: [Int64]) throws -> Set<Int64> {
        guard !trackIDs.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: trackIDs.count).joined(separator: ",")
        return try pool.read { db in
            Set(try Int64.fetchAll(
                db,
                sql: "SELECT track_id FROM local_cache WHERE track_id IN (\(placeholders))",
                arguments: StatementArguments(trackIDs)
            ))
        }
    }

    public func pageCachedTracks(
        query: String = "",
        sort: TrackSort = .title,
        direction: SortDirection = .ascending,
        offset: Int = 0,
        limit: Int = defaultPageSize
    ) throws -> TrackPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let safeOffset = max(0, offset)
        let searchPattern = Self.ftsPattern(query)
        return try pool.read { db in
            var from = "local_cache c JOIN tracks t ON t.id = c.track_id"
            var whereSQL = ""
            var arguments: StatementArguments = []
            if let searchPattern {
                from += " JOIN tracks_fts f ON f.rowid = t.id"
                whereSQL = " WHERE tracks_fts MATCH ?"
                arguments += [searchPattern]
            }
            let total = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM \(from)\(whereSQL)", arguments: arguments
            ) ?? 0
            var pageArguments = arguments
            pageArguments += [limit, safeOffset]
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT t.* FROM \(from)\(whereSQL) ORDER BY \(Self.orderSQL(sort, direction: direction)) LIMIT ? OFFSET ?",
                arguments: pageArguments
            )
            return TrackPage(
                tracks: rows.map(Self.decodeTrack), offset: safeOffset, limit: limit, totalCount: total
            )
        }
    }

    public func recordCachedTrack(trackID: Int64, path: String, fileSize: Int64, pinned: Bool = false) throws {
        try pool.write { db in
            let now = Date().timeIntervalSince1970
            try db.execute(sql: """
                INSERT INTO local_cache(track_id, local_path, file_size, cached_at, last_accessed_at, is_pinned)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(track_id) DO UPDATE SET local_path = excluded.local_path,
                    file_size = excluded.file_size, last_accessed_at = excluded.last_accessed_at,
                    is_pinned = CASE WHEN excluded.is_pinned = 1 THEN 1 ELSE local_cache.is_pinned END
                """, arguments: [trackID, path, fileSize, now, now, pinned])
        }
    }

    public func cachedTracksBeyondLimit(_ limit: Int) throws -> [(Int64, String)] {
        try pool.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT track_id, local_path FROM local_cache WHERE is_pinned = 0 ORDER BY last_accessed_at DESC LIMIT -1 OFFSET ?",
                arguments: [max(0, limit)]
            ).map { ($0["track_id"], $0["local_path"]) }
        }
    }

    public func setCachedTrackPinned(trackID: Int64, pinned: Bool) throws {
        try pool.write { db in
            try db.execute(
                sql: "UPDATE local_cache SET is_pinned = ? WHERE track_id = ?",
                arguments: [pinned, trackID]
            )
        }
    }

    public func isCachedTrackPinned(trackID: Int64) throws -> Bool {
        try pool.read { db in
            (try Bool.fetchOne(
                db,
                sql: "SELECT is_pinned FROM local_cache WHERE track_id = ?",
                arguments: [trackID]
            )) ?? false
        }
    }

    public func removeCachedTrack(trackID: Int64) throws {
        try pool.write { db in try db.execute(sql: "DELETE FROM local_cache WHERE track_id = ?", arguments: [trackID]) }
    }

    public func pageTracksAfter(
        query: String = "",
        sort: TrackSort = .title,
        direction: SortDirection = .ascending,
        after cursor: Track?,
        logicalOffset: Int = 0,
        limit: Int = defaultPageSize,
        availableOnly: Bool = false,
        knownTotal: Int? = nil
    ) throws -> TrackPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let searchPattern = Self.ftsPattern(query)
        return try pool.read { db in
            var baseWhere: [String] = []
            var baseArguments: StatementArguments = []
            var from = "tracks t"
            if let searchPattern {
                from += " JOIN tracks_fts f ON f.rowid = t.id"
                baseWhere.append("tracks_fts MATCH ?")
                baseArguments += [searchPattern]
            }
            if availableOnly { baseWhere.append("t.is_available = 1") }
            let countWhere = baseWhere.isEmpty ? "" : " WHERE " + baseWhere.joined(separator: " AND ")
            let total: Int
            if let knownTotal {
                total = knownTotal
            } else {
                total = try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM \(from)\(countWhere)", arguments: baseArguments
                ) ?? 0
            }

            var pageWhere = baseWhere
            var pageArguments = baseArguments
            if let cursor {
                let predicate = Self.cursorPredicate(sort: sort, direction: direction, cursor: cursor)
                pageWhere.append(predicate.sql)
                pageArguments += predicate.arguments
            }
            let whereSQL = pageWhere.isEmpty ? "" : " WHERE " + pageWhere.joined(separator: " AND ")
            pageArguments += [limit]
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT t.* FROM \(from)\(whereSQL) ORDER BY \(Self.orderSQL(sort, direction: direction)) LIMIT ?",
                arguments: pageArguments
            )
            return TrackPage(
                tracks: rows.map(Self.decodeTrack), offset: max(0, logicalOffset),
                limit: limit, totalCount: total
            )
        }
    }

    public func facetPage(
        section: LibrarySection,
        offset: Int = 0,
        limit: Int = defaultPageSize
    ) throws -> FacetPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let expression: String
        switch section {
        case .albums: expression = "album"
        case .artists: expression = "artist"
        case .genres: expression = "genre"
        case .folders: expression = "CASE WHEN instr(relative_path, '/') > 0 THEN substr(relative_path, 1, instr(relative_path, '/') - 1) ELSE '/' END"
        default: return FacetPage(facets: [], offset: 0, limit: limit, totalCount: 0)
        }
        let safeOffset = max(0, offset)
        return try pool.read { db in
            let total = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM (
                    SELECT 1 FROM tracks
                    WHERE is_available = 1 AND \(expression) <> ''
                    GROUP BY \(expression) COLLATE NOCASE
                )
                """) ?? 0
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT \(expression) AS name, COUNT(*) AS count
                    FROM tracks
                    WHERE is_available = 1 AND \(expression) <> ''
                    GROUP BY \(expression)
                    ORDER BY name COLLATE NOCASE
                    LIMIT ? OFFSET ?
                    """,
                arguments: [limit, safeOffset]
            )
            return FacetPage(
                facets: rows.map { Facet(name: $0["name"], count: $0["count"]) },
                offset: safeOffset, limit: limit, totalCount: total
            )
        }
    }

    public func pageAlbums(
        artistFilter: String? = nil,
        genreFilter: String? = nil,
        sort: AlbumSort = .name,
        direction: SortDirection = .ascending,
        offset: Int = 0,
        limit: Int = defaultPageSize
    ) throws -> AlbumSummaryPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let safeOffset = max(0, offset)
        return try pool.read { db in
            let expression = "artist"
            var filters: [String] = []
            var filterArgs: StatementArguments = []
            if let artistFilter {
                filters.append("(artist = ? COLLATE NOCASE OR album_artist = ? COLLATE NOCASE)")
                filterArgs += [artistFilter, artistFilter]
            }
            if let genreFilter {
                filters.append("genre = ? COLLATE NOCASE")
                filterArgs += [genreFilter]
            }
            let filterSQL = filters.map { " AND \($0)" }.joined()
            let total = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM (
                    SELECT 1 FROM tracks
                    WHERE is_available = 1 AND album <> ''\(filterSQL)
                    GROUP BY album COLLATE NOCASE, \(expression) COLLATE NOCASE
                )
                """, arguments: filterArgs) ?? 0
            var args = filterArgs
            args += [limit, safeOffset]
            
            let sortDir = direction == .ascending ? "ASC" : "DESC"
            let orderClause: String
            switch sort {
            case .name:
                orderClause = "name COLLATE NOCASE \(sortDir), artist COLLATE NOCASE \(sortDir)"
            case .artist:
                orderClause = "artist COLLATE NOCASE \(sortDir), name COLLATE NOCASE \(sortDir)"
            case .trackCount:
                orderClause = "track_count \(sortDir), name COLLATE NOCASE \(sortDir)"
            }

            let rows = try Row.fetchAll(db, sql: """
                SELECT album AS name, \(expression) AS artist, COUNT(*) AS track_count
                FROM tracks
                WHERE is_available = 1 AND album <> ''\(filterSQL)
                GROUP BY album COLLATE NOCASE, \(expression) COLLATE NOCASE
                ORDER BY \(orderClause)
                LIMIT ? OFFSET ?
                """, arguments: args)
            return AlbumSummaryPage(
                albums: rows.map { AlbumSummary(name: $0["name"], artist: $0["artist"], trackCount: $0["track_count"]) },
                offset: safeOffset, limit: limit, totalCount: total
            )
        }
    }

    public func pageArtists(
        genreFilter: String? = nil,
        search: String? = nil,
        sort: ArtistSort = .name,
        direction: SortDirection = .ascending,
        offset: Int = 0,
        limit: Int = defaultPageSize
    ) throws -> ArtistSummaryPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let safeOffset = max(0, offset)
        return try pool.read { db in
            var filters = ["is_available = 1"]
            var filterArgs: StatementArguments = []
            if let genreFilter {
                filters.append("genre = ? COLLATE NOCASE")
                filterArgs += [genreFilter]
            }
            let trimmedSearch = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmedSearch.isEmpty {
                filters.append("artist LIKE ? ESCAPE '\\' COLLATE NOCASE")
                let escaped = trimmedSearch
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                filterArgs += ["%\(escaped)%"]
            }
            let filterSQL = filters.joined(separator: " AND ")
            let sortExpression = "CASE WHEN lower(artist) LIKE 'the %' THEN substr(artist, 5) ELSE artist END"
            let total = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(DISTINCT artist COLLATE NOCASE) FROM tracks WHERE \(filterSQL)",
                arguments: filterArgs
            ) ?? 0
            var pageArguments = filterArgs
            pageArguments += [limit, safeOffset]
            
            let sortDir = direction == .ascending ? "ASC" : "DESC"
            let orderClause: String
            switch sort {
            case .name:
                orderClause = "\(sortExpression) COLLATE NOCASE \(sortDir), artist COLLATE NOCASE \(sortDir)"
            case .albumCount:
                orderClause = "album_count \(sortDir), \(sortExpression) COLLATE NOCASE \(sortDir)"
            case .trackCount:
                orderClause = "track_count \(sortDir), \(sortExpression) COLLATE NOCASE \(sortDir)"
            }

            let rows = try Row.fetchAll(db, sql: """
                SELECT artist AS name, COUNT(DISTINCT NULLIF(album, '')) AS album_count, COUNT(*) AS track_count
                FROM tracks
                WHERE \(filterSQL)
                GROUP BY artist COLLATE NOCASE
                ORDER BY \(orderClause)
                LIMIT ? OFFSET ?
                """, arguments: pageArguments)
            return ArtistSummaryPage(
                artists: rows.map { ArtistSummary(name: $0["name"], albumCount: $0["album_count"], trackCount: $0["track_count"]) },
                offset: safeOffset, limit: limit, totalCount: total
            )
        }
    }

    public func artistSummary(named name: String) throws -> ArtistSummary? {
        try pool.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT artist AS name, COUNT(DISTINCT NULLIF(album, '')) AS album_count, COUNT(*) AS track_count
                FROM tracks WHERE is_available = 1 AND artist = ? COLLATE NOCASE
                GROUP BY artist COLLATE NOCASE
                """, arguments: [name]) else { return nil }
            return ArtistSummary(name: row["name"], albumCount: row["album_count"], trackCount: row["track_count"])
        }
    }

    public func libraryStorageSummary(
        albumFilter: AlbumSummary? = nil,
        artistFilter: String? = nil,
        genreFilter: String? = nil
    ) throws -> LibraryStorageSummary {
        try pool.read { db in
            let albumArtistExpression = "COALESCE(NULLIF(t.album_artist, ''), t.artist)"
            var predicates = ["t.is_available = 1"]
            var arguments: StatementArguments = []
            if let albumFilter {
                predicates += ["t.album = ? COLLATE NOCASE", "\(albumArtistExpression) = ? COLLATE NOCASE"]
                arguments += [albumFilter.name, albumFilter.artist]
            } else if let artistFilter {
                predicates.append("t.artist = ? COLLATE NOCASE")
                arguments += [artistFilter]
            }
            if let genreFilter {
                predicates.append("t.genre = ? COLLATE NOCASE")
                arguments += [genreFilter]
            }
            let whereSQL = predicates.joined(separator: " AND ")
            let totalBytes = try Int64.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(t.file_size), 0) FROM tracks t WHERE \(whereSQL)",
                arguments: arguments
            ) ?? 0
            let paths = try String.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT r.last_known_path
                    FROM tracks t
                    JOIN scan_roots r ON r.id = t.root_id
                    WHERE \(whereSQL)
                    ORDER BY r.last_known_path COLLATE NOCASE
                    """,
                arguments: arguments
            )
            return LibraryStorageSummary(totalBytes: totalBytes, absoluteRootPaths: paths)
        }
    }

    public func pageTracksForArtist(
        artist: String,
        sort: TrackSort = .artist,
        direction: SortDirection = .ascending,
        offset: Int = 0,
        limit: Int = defaultPageSize
    ) throws -> TrackPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let safeOffset = max(0, offset)
        return try pool.read { db in
            let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tracks WHERE is_available = 1 AND (artist = ? COLLATE NOCASE OR album_artist = ? COLLATE NOCASE)", arguments: [artist, artist]) ?? 0
            let rows = try Row.fetchAll(db, sql: """
                SELECT t.* FROM tracks t WHERE t.is_available = 1 AND (t.artist = ? COLLATE NOCASE OR t.album_artist = ? COLLATE NOCASE)
                ORDER BY \(Self.orderSQL(sort, direction: direction)) LIMIT ? OFFSET ?
                """, arguments: [artist, artist, limit, safeOffset])
            return TrackPage(tracks: rows.map(Self.decodeTrack), offset: safeOffset, limit: limit, totalCount: total)
        }
    }

    public func pageTracksForGenre(
        genre: String,
        sort: TrackSort = .album,
        direction: SortDirection = .ascending,
        offset: Int = 0,
        limit: Int = defaultPageSize
    ) throws -> TrackPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let safeOffset = max(0, offset)
        return try pool.read { db in
            let total = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM tracks WHERE is_available = 1 AND genre = ? COLLATE NOCASE",
                arguments: [genre]
            ) ?? 0
            let rows = try Row.fetchAll(db, sql: """
                SELECT t.* FROM tracks t
                WHERE t.is_available = 1 AND t.genre = ? COLLATE NOCASE
                ORDER BY \(Self.orderSQL(sort, direction: direction)) LIMIT ? OFFSET ?
                """, arguments: [genre, limit, safeOffset])
            return TrackPage(tracks: rows.map(Self.decodeTrack), offset: safeOffset, limit: limit, totalCount: total)
        }
    }

    public func offsetForTrackTitle(
        startingAt value: String,
        albumFilter: AlbumSummary? = nil,
        artistFilter: String? = nil,
        genreFilter: String? = nil,
        availableOnly: Bool = false
    ) throws -> Int {
        try pool.read { db in
            let albumArtistExpression = "COALESCE(NULLIF(t.album_artist, ''), t.artist)"
            var predicates: [String] = []
            var arguments: StatementArguments = []
            if availableOnly { predicates.append("t.is_available = 1") }
            if let albumFilter {
                predicates += ["t.album = ? COLLATE NOCASE", "\(albumArtistExpression) = ? COLLATE NOCASE"]
                arguments += [albumFilter.name, albumFilter.artist]
            }
            if let artistFilter {
                predicates.append("t.artist = ? COLLATE NOCASE")
                arguments += [artistFilter]
            }
            if let genreFilter {
                predicates.append("t.genre = ? COLLATE NOCASE")
                arguments += [genreFilter]
            }
            predicates.append("t.title < ? COLLATE NOCASE")
            arguments += [value]
            return try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM tracks t WHERE \(predicates.joined(separator: " AND "))",
                arguments: arguments
            ) ?? 0
        }
    }

    public func offsetForAlbum(
        startingAt value: String,
        artistFilter: String? = nil,
        genreFilter: String? = nil
    ) throws -> Int {
        try pool.read { db in
            let expression = "COALESCE(NULLIF(album_artist, ''), artist)"
            var predicates = ["is_available = 1", "album <> ''", "album < ? COLLATE NOCASE"]
            var arguments: StatementArguments = [value]
            if let artistFilter {
                predicates.append("\(expression) = ? COLLATE NOCASE")
                arguments += [artistFilter]
            }
            if let genreFilter {
                predicates.append("genre = ? COLLATE NOCASE")
                arguments += [genreFilter]
            }
            return try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM (
                    SELECT 1 FROM tracks WHERE \(predicates.joined(separator: " AND "))
                    GROUP BY album COLLATE NOCASE, \(expression) COLLATE NOCASE
                )
                """, arguments: arguments) ?? 0
        }
    }

    public func offsetForArtist(startingAt value: String, genreFilter: String? = nil, search: String? = nil) throws -> Int {
        try pool.read { db in
            let sortExpression = "CASE WHEN lower(artist) LIKE 'the %' THEN substr(artist, 5) ELSE artist END"
            var predicates = ["is_available = 1", "\(sortExpression) < ? COLLATE NOCASE"]
            var arguments: StatementArguments = [value]
            if let genreFilter {
                predicates.append("genre = ? COLLATE NOCASE")
                arguments += [genreFilter]
            }
            let trimmedSearch = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmedSearch.isEmpty {
                predicates.append("artist LIKE ? ESCAPE '\\' COLLATE NOCASE")
                let escaped = trimmedSearch
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_")
                arguments += ["%\(escaped)%"]
            }
            return try Int.fetchOne(
                db,
                sql: "SELECT COUNT(DISTINCT artist COLLATE NOCASE) FROM tracks WHERE \(predicates.joined(separator: " AND "))",
                arguments: arguments
            ) ?? 0
        }
    }

    public func pageTracksForAlbum(
        album: AlbumSummary,
        sort: TrackSort = .album,
        direction: SortDirection = .ascending,
        offset: Int = 0,
        limit: Int = defaultPageSize
    ) throws -> TrackPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let safeOffset = max(0, offset)
        return try pool.read { db in
            let artistExpression = "COALESCE(NULLIF(t.album_artist, ''), t.artist)"
            let arguments: StatementArguments = [album.name, album.artist]
            let total = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tracks t WHERE t.is_available = 1 AND t.album = ? COLLATE NOCASE AND \(artistExpression) = ? COLLATE NOCASE", arguments: arguments) ?? 0
            var pageArguments = arguments
            pageArguments += [limit, safeOffset]
            let rows = try Row.fetchAll(db, sql: """
                SELECT t.* FROM tracks t
                WHERE t.is_available = 1 AND t.album = ? COLLATE NOCASE AND \(artistExpression) = ? COLLATE NOCASE
                ORDER BY \(Self.orderSQL(sort, direction: direction)) LIMIT ? OFFSET ?
                """, arguments: pageArguments)
            return TrackPage(tracks: rows.map(Self.decodeTrack), offset: safeOffset, limit: limit, totalCount: total)
        }
    }

    public func upsertTracks(_ imports: [TrackImport], sessionID: Int64) throws -> Int {
        guard !imports.isEmpty else { return 0 }
        return try pool.write { db in
            var changed = 0
            for item in imports {
                if try Bool.fetchOne(
                    db, sql: "SELECT EXISTS(SELECT 1 FROM excluded_tracks WHERE identity_key = ?)",
                    arguments: [item.identityKey]
                ) == true { continue }
                changed += try Self.upsertTrackAndLog(db: db, item: item, sessionID: sessionID)
            }
            try Self.refreshDimensions(db: db, imports: imports)
            try Self.pruneActivityLog(db: db)
            return changed
        }
    }

    public func signature(identityKey: String) throws -> (size: Int64, modifiedAt: Date)? {
        try pool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT file_size, modified_at FROM tracks WHERE identity_key = ?",
                arguments: [identityKey]
            ) else { return nil }
            return (row["file_size"], Date(timeIntervalSince1970: row["modified_at"]))
        }
    }

    public func markSeen(identityKey: String, sessionID: Int64) throws {
        try pool.write { db in
            let previous = try Row.fetchOne(
                db, sql: "SELECT * FROM tracks WHERE identity_key = ?", arguments: [identityKey]
            )
            try db.execute(
                sql: "UPDATE tracks SET last_seen_session_id = ?, is_available = 1 WHERE identity_key = ?",
                arguments: [sessionID, identityKey]
            )
            if let previous, previous["is_available"] as Bool == false,
               let updated = try Row.fetchOne(db, sql: "SELECT * FROM tracks WHERE identity_key = ?", arguments: [identityKey]) {
                try Self.insertActivity(db: db, kind: .restored, trackRow: updated, changes: [])
                try Self.pruneActivityLog(db: db)
            }
        }
    }

    public func commitScanBatch(
        imports: [TrackImport],
        unchangedIdentityKeys: [String],
        sessionID: Int64
    ) throws -> Int {
        guard !imports.isEmpty || !unchangedIdentityKeys.isEmpty else { return 0 }
        return try pool.write { db in
            var changed = 0
            for item in imports {
                if try Bool.fetchOne(
                    db, sql: "SELECT EXISTS(SELECT 1 FROM excluded_tracks WHERE identity_key = ?)",
                    arguments: [item.identityKey]
                ) == true { continue }
                changed += try Self.upsertTrackAndLog(db: db, item: item, sessionID: sessionID)
            }
            for identityKey in unchangedIdentityKeys {
                let previous = try Row.fetchOne(
                    db, sql: "SELECT * FROM tracks WHERE identity_key = ?", arguments: [identityKey]
                )
                try db.execute(
                    sql: "UPDATE tracks SET last_seen_session_id = ?, is_available = 1 WHERE identity_key = ?",
                    arguments: [sessionID, identityKey]
                )
                if let previous, previous["is_available"] as Bool == false,
                   let updated = try Row.fetchOne(db, sql: "SELECT * FROM tracks WHERE identity_key = ?", arguments: [identityKey]) {
                    try Self.insertActivity(db: db, kind: .restored, trackRow: updated, changes: [])
                }
            }
            try Self.refreshDimensions(db: db, imports: imports)
            try Self.pruneActivityLog(db: db)
            return changed
        }
    }

    public func markMissingTracks(rootID: Int64, sessionID: Int64) throws -> Int {
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO library_activity_log(
                        kind, track_id, root_id, relative_path, absolute_path, filename,
                        title, artist, album, changes_json, occurred_at
                    )
                    SELECT ?, t.id, t.root_id, t.relative_path,
                        CASE WHEN COALESCE(r.last_known_path, '') = '' THEN t.relative_path
                             ELSE rtrim(r.last_known_path, '/') || '/' || t.relative_path END,
                        t.filename, t.title, t.artist, t.album, '[]', ?
                    FROM tracks t
                    LEFT JOIN scan_roots r ON r.id = t.root_id
                    WHERE t.root_id = ? AND t.is_available = 1
                      AND COALESCE(t.last_seen_session_id, 0) <> ?
                    """,
                arguments: [LibraryActivityKind.unavailable.rawValue, Date().timeIntervalSince1970, rootID, sessionID]
            )
            try db.execute(
                sql: "UPDATE tracks SET is_available = 0 WHERE root_id = ? AND is_available = 1 AND COALESCE(last_seen_session_id, 0) <> ?",
                arguments: [rootID, sessionID]
            )
            let changed = db.changesCount
            try Self.pruneActivityLog(db: db)
            return changed
        }
    }

    public func addScanRoot(
        displayName: String,
        bookmark: Data,
        volumeUUID: String?,
        path: String
    ) throws -> Int64 {
        let normalizedPath = path.precomposedStringWithCanonicalMapping
        return try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO scan_roots(display_name, bookmark, volume_uuid, last_known_path, is_available, created_at)
                    VALUES (?, ?, ?, ?, 1, ?)
                    ON CONFLICT(last_known_path) DO UPDATE SET
                        display_name = excluded.display_name,
                        bookmark = excluded.bookmark,
                        volume_uuid = excluded.volume_uuid,
                        is_available = 1
                    """,
                arguments: [displayName, bookmark, volumeUUID, normalizedPath, Date().timeIntervalSince1970]
            )
            return db.lastInsertedRowID != 0
                ? db.lastInsertedRowID
                : (try Int64.fetchOne(db, sql: "SELECT id FROM scan_roots WHERE last_known_path = ?", arguments: [normalizedPath]) ?? 0)
        }
    }

    public func scanRoots() throws -> [ScanRoot] {
        try pool.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM scan_roots ORDER BY id").map { row in
                ScanRoot(
                    id: row["id"],
                    displayName: row["display_name"],
                    bookmark: row["bookmark"],
                    volumeUUID: row["volume_uuid"],
                    lastKnownPath: row["last_known_path"],
                    isAvailable: row["is_available"]
                )
            }
        }
    }

    public func scanRoot(id: Int64) throws -> ScanRoot? {
        try pool.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM scan_roots WHERE id = ?", arguments: [id]) else {
                return nil
            }
            return ScanRoot(
                id: row["id"], displayName: row["display_name"], bookmark: row["bookmark"],
                volumeUUID: row["volume_uuid"], lastKnownPath: row["last_known_path"],
                isAvailable: row["is_available"]
            )
        }
    }

    public func setRootAvailability(id: Int64, isAvailable: Bool, path: String? = nil) throws {
        try pool.write { db in
            try db.execute(
                sql: "UPDATE scan_roots SET is_available = ?, last_known_path = COALESCE(?, last_known_path) WHERE id = ?",
                arguments: [isAvailable, path, id]
            )
        }
    }

    public func updateScanRootAuthorization(id: Int64, bookmark: Data, path: String) throws {
        try pool.write { db in
            try db.execute(
                sql: "UPDATE scan_roots SET bookmark = ?, last_known_path = ?, is_available = 1 WHERE id = ?",
                arguments: [bookmark, path, id]
            )
        }
    }

    public func createScanSession(rootID: Int64, resumeCursor: String? = nil) throws -> Int64 {
        try pool.write { db in
            try db.execute(
                sql: """
                    INSERT INTO scan_sessions(root_id, state, started_at, resume_cursor, discovered, processed, changed_count, skipped, error_count)
                    VALUES (?, 'running', ?, ?, 0, 0, 0, 0, 0)
                    """,
                arguments: [rootID, Date().timeIntervalSince1970, resumeCursor]
            )
            return db.lastInsertedRowID
        }
    }

    public func resumableSession(rootID: Int64) throws -> (id: Int64, cursor: String?)? {
        try pool.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT id, resume_cursor FROM scan_sessions
                    WHERE root_id = ? AND state IN ('running', 'paused', 'cancelled', 'failed')
                    ORDER BY id DESC LIMIT 1
                    """,
                arguments: [rootID]
            ) else { return nil }
            return (row["id"], row["resume_cursor"])
        }
    }

    public func updateScanSession(
        id: Int64,
        state: ScanState,
        cursor: String?,
        discovered: Int,
        processed: Int,
        changed: Int,
        skipped: Int,
        errors: Int,
        finished: Bool = false
    ) throws {
        try pool.write { db in
            try db.execute(
                sql: """
                    UPDATE scan_sessions SET state = ?, resume_cursor = ?, discovered = ?, processed = ?,
                        changed_count = ?, skipped = ?, error_count = ?, finished_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    state.rawValue, cursor, discovered, processed, changed, skipped, errors,
                    finished ? Date().timeIntervalSince1970 : nil, id
                ]
            )
        }
    }

    public func recordScanError(sessionID: Int64, path: String, message: String) throws {
        try pool.write { db in
            try db.execute(
                sql: "INSERT INTO scan_errors(session_id, path, message, created_at) VALUES (?, ?, ?, ?)",
                arguments: [sessionID, path, String(message.prefix(2_000)), Date().timeIntervalSince1970]
            )
        }
    }

    public func playlists() throws -> [Playlist] {
        try pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT p.id, p.name, COUNT(i.id) AS item_count
                FROM playlists p LEFT JOIN playlist_items i ON i.playlist_id = p.id
                GROUP BY p.id ORDER BY p.name COLLATE NOCASE
                """)
            return rows.map { Playlist(id: $0["id"], name: $0["name"], itemCount: $0["item_count"]) }
        }
    }

    public func createPlaylist(name: String) throws -> Int64 {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MassiveMusicError.invalidPlaylistName }
        return try pool.write { db in
            let now = Date().timeIntervalSince1970
            try db.execute(
                sql: "INSERT INTO playlists(name, created_at, updated_at) VALUES (?, ?, ?)",
                arguments: [trimmed, now, now]
            )
            return db.lastInsertedRowID
        }
    }

    public func renamePlaylist(id: Int64, name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MassiveMusicError.invalidPlaylistName }
        try pool.write { db in
            try db.execute(
                sql: "UPDATE playlists SET name = ?, updated_at = ? WHERE id = ?",
                arguments: [trimmed, Date().timeIntervalSince1970, id]
            )
        }
    }

    public func deletePlaylist(id: Int64) throws {
        try pool.write { db in
            try db.execute(sql: "DELETE FROM playlists WHERE id = ?", arguments: [id])
        }
    }

    public func addTracks(
        _ trackIDs: any Sequence<Int64>,
        toPlaylist playlistID: Int64,
        progress: (@Sendable (Int) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) throws -> Int {
        var iterator = trackIDs.makeIterator()
        var totalAdded = 0
        var nextPosition = try pool.read { db in
            (try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(position), -1) + 1 FROM playlist_items WHERE playlist_id = ?",
                arguments: [playlistID]
            )) ?? 0
        }
        while isCancelled?() != true {
            var chunk: [Int64] = []
            chunk.reserveCapacity(Self.playlistCommitSize)
            while chunk.count < Self.playlistCommitSize, let id = iterator.next() { chunk.append(id) }
            if chunk.isEmpty { break }
            let added = try pool.write { db in
                var count = 0
                for trackID in chunk {
                    try db.execute(
                        sql: "INSERT OR IGNORE INTO playlist_items(playlist_id, track_id, position, created_at) VALUES (?, ?, ?, ?)",
                        arguments: [playlistID, trackID, nextPosition, Date().timeIntervalSince1970]
                    )
                    count += db.changesCount
                    nextPosition += 1
                }
                try db.execute(
                    sql: "UPDATE playlists SET updated_at = ? WHERE id = ?",
                    arguments: [Date().timeIntervalSince1970, playlistID]
                )
                return count
            }
            totalAdded += added
            progress?(totalAdded)
        }
        return totalAdded
    }

    public func playlistTracks(
        playlistID: Int64,
        offset: Int,
        limit: Int = defaultPageSize,
        sort: TrackSort? = nil,
        direction: SortDirection = .ascending
    ) throws -> TrackPage {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        return try pool.read { db in
            let total = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM playlist_items WHERE playlist_id = ?",
                arguments: [playlistID]
            ) ?? 0
            let orderSQL = sort.map { Self.orderSQL($0, direction: direction) } ?? "i.position"
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT t.* FROM playlist_items i
                    JOIN tracks t ON t.id = i.track_id
                    WHERE i.playlist_id = ? ORDER BY \(orderSQL) LIMIT ? OFFSET ?
                    """,
                arguments: [playlistID, limit, max(0, offset)]
            )
            return TrackPage(tracks: rows.map(Self.decodeTrack), offset: max(0, offset), limit: limit, totalCount: total)
        }
    }

    public func removeTrack(_ trackID: Int64, fromPlaylist playlistID: Int64) throws {
        try pool.write { db in
            try db.execute(
                sql: "DELETE FROM playlist_items WHERE playlist_id = ? AND track_id = ?",
                arguments: [playlistID, trackID]
            )
            try db.execute(
                sql: """
                    WITH ranked AS (
                        SELECT id, ROW_NUMBER() OVER (ORDER BY position, id) - 1 AS new_position
                        FROM playlist_items WHERE playlist_id = ?
                    )
                    UPDATE playlist_items SET position = (SELECT new_position FROM ranked WHERE ranked.id = playlist_items.id)
                    WHERE playlist_id = ?
                    """,
                arguments: [playlistID, playlistID]
            )
        }
    }

    public func movePlaylistItem(playlistID: Int64, from: Int, to: Int) throws {
        guard from != to else { return }
        try pool.write { db in
            guard let itemID = try Int64.fetchOne(
                db,
                sql: "SELECT id FROM playlist_items WHERE playlist_id = ? AND position = ?",
                arguments: [playlistID, from]
            ) else { return }
            let temporaryOffset = (try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(position), 0) + 2 FROM playlist_items WHERE playlist_id = ?",
                arguments: [playlistID]
            )) ?? 2
            try db.execute(sql: "UPDATE playlist_items SET position = -1 WHERE id = ?", arguments: [itemID])
            if from < to {
                try db.execute(
                    sql: "UPDATE playlist_items SET position = position + ? WHERE playlist_id = ? AND position > ? AND position <= ?",
                    arguments: [temporaryOffset, playlistID, from, to]
                )
                try db.execute(
                    sql: "UPDATE playlist_items SET position = position - ? - 1 WHERE playlist_id = ? AND position > ? AND position <= ?",
                    arguments: [temporaryOffset, playlistID, temporaryOffset + from, temporaryOffset + to]
                )
            } else {
                try db.execute(
                    sql: "UPDATE playlist_items SET position = position + ? WHERE playlist_id = ? AND position >= ? AND position < ?",
                    arguments: [temporaryOffset, playlistID, to, from]
                )
                try db.execute(
                    sql: "UPDATE playlist_items SET position = position - ? + 1 WHERE playlist_id = ? AND position >= ? AND position < ?",
                    arguments: [temporaryOffset, playlistID, temporaryOffset + to, temporaryOffset + from]
                )
            }
            try db.execute(sql: "UPDATE playlist_items SET position = ? WHERE id = ?", arguments: [to, itemID])
        }
    }

    public func shuffleCandidates(afterID: Int64, seed: Int64, limit: Int = 100) throws -> [Track] {
        guard (1...1_000).contains(limit) else { throw MassiveMusicError.invalidPageSize }
        let bucket = abs(seed % 997)
        return try pool.read { db in
            var rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM tracks
                    WHERE is_available = 1 AND id > ?
                      AND ((id * 1103515245 + ?) & 2147483647) % 997 = ?
                    ORDER BY id LIMIT ?
                    """,
                arguments: [afterID, seed, bucket, limit]
            )
            if rows.count < limit {
                let remainder = limit - rows.count
                let wrapped = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT * FROM tracks
                        WHERE is_available = 1 AND id <= ?
                          AND ((id * 1103515245 + ?) & 2147483647) % 997 = ?
                        ORDER BY id LIMIT ?
                        """,
                    arguments: [afterID, seed, bucket, remainder]
                )
                rows.append(contentsOf: wrapped)
            }
            return rows.map(Self.decodeTrack)
        }
    }

    public func adjacentTrack(to id: Int64, direction: Int) throws -> Track? {
        try pool.read { db in
            let comparison = direction >= 0 ? ">" : "<"
            let ordering = direction >= 0 ? "ASC" : "DESC"
            let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM tracks WHERE is_available = 1 AND id \(comparison) ? ORDER BY id \(ordering) LIMIT 1",
                arguments: [id]
            ) ?? Row.fetchOne(
                db,
                sql: "SELECT * FROM tracks WHERE is_available = 1 ORDER BY id \(ordering) LIMIT 1"
            )
            return row.map(Self.decodeTrack)
        }
    }

    public func adjacentTrack(
        in context: TrackPlaybackContext,
        from current: Track,
        direction: Int
    ) throws -> Track? {
        let forward = direction >= 0
        let queryDirection: SortDirection
        if forward {
            queryDirection = context.direction
        } else {
            queryDirection = context.direction == .ascending ? .descending : .ascending
        }
        let cursor = Self.cursorPredicate(
            sort: context.sort,
            direction: queryDirection,
            cursor: current
        )

        return try pool.read { db in
            var from = "tracks t"
            var predicates: [String] = []
            var arguments: StatementArguments = []

            switch context.scope {
            case let .library(query):
                if let pattern = Self.ftsPattern(query) {
                    from += " JOIN tracks_fts f ON f.rowid = t.id"
                    predicates.append("tracks_fts MATCH ?")
                    arguments += [pattern]
                }
            case let .album(name, artist):
                predicates += [
                    "t.is_available = 1",
                    "t.album = ? COLLATE NOCASE",
                    "COALESCE(NULLIF(t.album_artist, ''), t.artist) = ? COLLATE NOCASE"
                ]
                arguments += [name, artist]
            case let .artist(name):
                predicates += ["t.is_available = 1", "t.artist = ? COLLATE NOCASE"]
                arguments += [name]
            case let .genre(name):
                predicates += ["t.is_available = 1", "t.genre = ? COLLATE NOCASE"]
                arguments += [name]
            case .favorites:
                predicates.append("t.is_favorite = 1")
            case let .cache(query):
                from = "local_cache c JOIN tracks t ON t.id = c.track_id"
                if let pattern = Self.ftsPattern(query) {
                    from += " JOIN tracks_fts f ON f.rowid = t.id"
                    predicates.append("tracks_fts MATCH ?")
                    arguments += [pattern]
                }
            case let .playlist(id):
                from = "playlist_items i JOIN tracks t ON t.id = i.track_id"
                predicates.append("i.playlist_id = ?")
                arguments += [id]
            case let .metadataIssue(kind):
                guard kind != .suspectedVariations else { return nil }
                predicates.append(Self.metadataIssuePredicate(kind))
            }

            predicates.append(cursor.sql)
            arguments += cursor.arguments
            let whereSQL = " WHERE " + predicates.joined(separator: " AND ")
            let row = try Row.fetchOne(
                db,
                sql: "SELECT t.* FROM \(from)\(whereSQL) ORDER BY \(Self.orderSQL(context.sort, direction: queryDirection)) LIMIT 1",
                arguments: arguments
            )
            return row.map(Self.decodeTrack)
        }
    }

    public func trackID(relativeOrAbsolutePath path: String) throws -> Int64? {
        try pool.read { db in
            if let id = try Int64.fetchOne(
                db,
                sql: "SELECT id FROM tracks WHERE relative_path = ? LIMIT 1",
                arguments: [path]
            ) { return id }
            return try Int64.fetchOne(
                db,
                sql: """
                    SELECT t.id FROM tracks t JOIN scan_roots r ON r.id = t.root_id
                    WHERE r.last_known_path || '/' || t.relative_path = ? LIMIT 1
                    """,
                arguments: [path]
            )
        }
    }

    public func insertSyntheticTracks(count: Int, rootID: Int64 = 1) throws -> Int {
        guard count > 0 else { return 0 }
        var inserted = 0
        while inserted < count {
            let upperBound = min(inserted + Self.playlistCommitSize, count)
            try pool.write { db in
                for index in inserted..<upperBound {
                    let artist = "Artist \(index % 12_000)"
                    let album = "Album \(index % 48_000)"
                    let genre = "Genre \(index % 40)"
                    let identity = "synthetic:\(index)"
                    try db.execute(
                        sql: SQL.upsertTrack,
                        arguments: [
                            rootID, identity, nil, "Synthetic/\(index / 1_000)/track-\(index).mp3",
                            "track-\(index).mp3", "Synthetic Track \(index)", artist, album, artist,
                            genre, 1, (index % 20) + 1, Double(120 + index % 300), 4_000_000,
                            1_700_000_000 + Double(index), "mp3", 320_000, index % 3 == 0, true,
                            1_700_000_000 + Double(index), 0
                        ]
                    )
                }
            }
            inserted = upperBound
        }
        return inserted
    }

    public func benchmarkSynthetic(count: Int) throws -> SyntheticBenchmarkResult {
        let insertStart = ContinuousClock.now
        let before = try trackCount()
        _ = try insertSyntheticTracks(count: count)
        let insertDuration = ContinuousClock.now - insertStart

        let searchStart = ContinuousClock.now
        _ = try pageTracks(query: "Synthetic Track 359", limit: 100)
        let searchDuration = ContinuousClock.now - searchStart

        let firstPage = try pageTracksAfter(sort: .artist, after: nil, limit: 200)
        let pageStart = ContinuousClock.now
        _ = try pageTracksAfter(
            sort: .artist, after: firstPage.tracks.last, logicalOffset: 200,
            limit: 200, knownTotal: firstPage.totalCount
        )
        let pageDuration = ContinuousClock.now - pageStart

        let deepOffsetStart = ContinuousClock.now
        _ = try pageTracks(sort: .artist, offset: max(0, count - 200), limit: 200)
        let deepOffsetDuration = ContinuousClock.now - deepOffsetStart
        let playlistStart = ContinuousClock.now
        let playlistID = try createPlaylist(name: "100k benchmark")
        let playlistCount = min(count, 100_000)
        _ = try addTracks(Int64(1)...Int64(playlistCount), toPlaylist: playlistID)
        let playlistDuration = ContinuousClock.now - playlistStart
        let playlistPageStart = ContinuousClock.now
        _ = try playlistTracks(playlistID: playlistID, offset: max(0, playlistCount - 200), limit: 200)
        let playlistPageDuration = ContinuousClock.now - playlistPageStart
        let attributes = try FileManager.default.attributesOfItem(atPath: databaseURL.path)
        let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        return SyntheticBenchmarkResult(
            requestedCount: count,
            insertedCount: try trackCount() - before,
            insertSeconds: Self.seconds(insertDuration),
            searchMilliseconds: Self.seconds(searchDuration) * 1_000,
            pageMilliseconds: Self.seconds(pageDuration) * 1_000,
            deepOffsetMilliseconds: Self.seconds(deepOffsetDuration) * 1_000,
            playlist100kSeconds: Self.seconds(playlistDuration),
            playlistPageMilliseconds: Self.seconds(playlistPageDuration) * 1_000,
            databaseBytes: bytes,
            generatedAt: Date()
        )
    }

    public func inTransactionForTesting(_ operation: @escaping @Sendable () throws -> Void) throws {
        try pool.write { _ in try operation() }
    }

    public func rollbackProbeForTesting() throws -> Bool {
        enum ProbeError: Error { case expected }
        let identity = "rollback-probe-\(UUID().uuidString)"
        do {
            try pool.write { db in
                try db.execute(
                    sql: """
                        INSERT INTO tracks(
                            root_id, identity_key, relative_path, filename, title, file_size,
                            modified_at, format, added_at
                        ) VALUES (0, ?, 'probe.mp3', 'probe.mp3', 'Probe', 1, 0, 'mp3', 0)
                        """,
                    arguments: [identity]
                )
                throw ProbeError.expected
            }
        } catch ProbeError.expected {
            // Expected: GRDB must roll the transaction back.
        }
        return try pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tracks WHERE identity_key = ?", arguments: [identity]) == 0
        }
    }

    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    private static func orderSQL(_ sort: TrackSort, direction: SortDirection) -> String {
        let order = direction == .ascending ? "ASC" : "DESC"
        return switch sort {
        case .title: "t.title COLLATE NOCASE \(order), t.id \(order)"
        case .artist: "t.artist COLLATE NOCASE \(order), t.album COLLATE NOCASE \(order), t.disc_number \(order), t.track_number \(order), t.id \(order)"
        case .album: "t.album COLLATE NOCASE \(order), t.disc_number \(order), t.track_number \(order), t.id \(order)"
        case .discNumber: "COALESCE(t.disc_number, -1) \(order), COALESCE(t.track_number, -1) \(order), t.id \(order)"
        case .trackNumber: "COALESCE(t.track_number, -1) \(order), COALESCE(t.disc_number, -1) \(order), t.id \(order)"
        case .dateAdded: "t.added_at \(order), t.id \(order)"
        case .path: "t.relative_path COLLATE NOCASE \(order), t.id \(order)"
        case .duration: "t.duration \(order), t.id \(order)"
        case .format: "t.format COLLATE NOCASE \(order), t.title COLLATE NOCASE \(order), t.id \(order)"
        }
    }

    private static func metadataIssuePredicate(_ kind: MetadataIssueKind) -> String {
        switch kind {
        case .missingTitle: "trim(t.title) = ''"
        case .missingArtist: "trim(t.artist) = ''"
        case .missingAlbum: "trim(t.album) = ''"
        case .urlInMP3Metadata:
            """
            lower(t.format) = 'mp3' AND (
                instr(lower(t.title || ' ' || t.artist || ' ' || t.album || ' ' || t.album_artist || ' ' || t.genre || ' ' || t.filename), 'http') > 0
                OR instr(lower(t.title || ' ' || t.artist || ' ' || t.album || ' ' || t.album_artist || ' ' || t.genre || ' ' || t.filename), 'www.') > 0
            )
            """
        case .duplicateTracks:
            """
            EXISTS (
                SELECT 1 FROM tracks t2
                WHERE t2.is_available = 1 AND t2.id <> t.id
                  AND t2.title = t.title COLLATE NOCASE
                  AND t2.artist = t.artist COLLATE NOCASE
                  AND t2.album = t.album COLLATE NOCASE
            )
            """
        case .suspectedVariations: "0"
        }
    }

    private static func metadataColumn(_ field: MetadataField) -> String {
        switch field { case .title: "title"; case .artist: "artist"; case .album: "album" }
    }

    private static func ftsPattern(_ query: String) -> String? {
        let terms = query
            .split(whereSeparator: { $0.isWhitespace })
            .map { $0.replacingOccurrences(of: "\"", with: "\"\"") }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return nil }
        return terms.map { "\"\($0)\"*" }.joined(separator: " AND ")
    }

    private static func cursorPredicate(sort: TrackSort, direction: SortDirection, cursor: Track) -> (sql: String, arguments: StatementArguments) {
        let comparison = direction == .ascending ? ">" : "<"
        switch sort {
        case .title:
            return (
                "(t.title COLLATE NOCASE, t.id) \(comparison) (? COLLATE NOCASE, ?)",
                [cursor.title, cursor.id]
            )
        case .artist:
            return (
                """
                (t.artist COLLATE NOCASE, t.album COLLATE NOCASE, COALESCE(t.disc_number, -1),
                 COALESCE(t.track_number, -1), t.id) \(comparison) (? COLLATE NOCASE, ? COLLATE NOCASE, ?, ?, ?)
                """,
                [cursor.artist, cursor.album, cursor.discNumber ?? -1, cursor.trackNumber ?? -1, cursor.id]
            )
        case .album:
            return (
                """
                (t.album COLLATE NOCASE, COALESCE(t.disc_number, -1), COALESCE(t.track_number, -1), t.id)
                \(comparison) (? COLLATE NOCASE, ?, ?, ?)
                """,
                [cursor.album, cursor.discNumber ?? -1, cursor.trackNumber ?? -1, cursor.id]
            )
        case .discNumber:
            return (
                "(COALESCE(t.disc_number, -1), COALESCE(t.track_number, -1), t.id) \(comparison) (?, ?, ?)",
                [cursor.discNumber ?? -1, cursor.trackNumber ?? -1, cursor.id]
            )
        case .trackNumber:
            return (
                "(COALESCE(t.track_number, -1), COALESCE(t.disc_number, -1), t.id) \(comparison) (?, ?, ?)",
                [cursor.trackNumber ?? -1, cursor.discNumber ?? -1, cursor.id]
            )
        case .dateAdded:
            return ("(t.added_at, t.id) \(comparison) (?, ?)", [cursor.addedAt.timeIntervalSince1970, cursor.id])
        case .path:
            return (
                "(t.relative_path COLLATE NOCASE, t.id) \(comparison) (? COLLATE NOCASE, ?)",
                [cursor.relativePath, cursor.id]
            )
        case .duration:
            return ("(t.duration, t.id) \(comparison) (?, ?)", [cursor.duration, cursor.id])
        case .format:
            return (
                "(t.format COLLATE NOCASE, t.title COLLATE NOCASE, t.id) \(comparison) (? COLLATE NOCASE, ? COLLATE NOCASE, ?)",
                [cursor.format, cursor.title, cursor.id]
            )
        }
    }

    private static func decodeTrack(_ row: Row) -> Track {
        Track(
            id: row["id"], rootID: row["root_id"], relativePath: row["relative_path"],
            filename: row["filename"], title: row["title"], artist: row["artist"],
            album: row["album"], albumArtist: row["album_artist"], genre: row["genre"],
            discNumber: row["disc_number"], trackNumber: row["track_number"],
            duration: row["duration"], fileSize: row["file_size"],
            modifiedAt: Date(timeIntervalSince1970: row["modified_at"]), format: row["format"],
            bitrate: row["bitrate"], hasArtwork: row["has_artwork"], isAvailable: row["is_available"],
            addedAt: Date(timeIntervalSince1970: row["added_at"]),
            isFavorite: row.hasColumn("is_favorite") ? row["is_favorite"] : false
        )
    }

    private static func decodeActivityEvent(_ row: Row) -> LibraryActivityEvent {
        let json: String = row["changes_json"]
        let changes = (try? JSONDecoder().decode(
            [LibraryActivityChange].self, from: Data(json.utf8)
        )) ?? []
        return LibraryActivityEvent(
            id: row["id"],
            kind: LibraryActivityKind(rawValue: row["kind"]) ?? .fileModified,
            trackID: row["track_id"],
            filename: row["filename"],
            title: row["title"],
            artist: row["artist"],
            album: row["album"],
            relativePath: row["relative_path"],
            absolutePath: row["absolute_path"],
            changes: changes,
            occurredAt: Date(timeIntervalSince1970: row["occurred_at"])
        )
    }

    private static func upsertTrackAndLog(
        db: Database, item: TrackImport, sessionID: Int64
    ) throws -> Int {
        let previous = try Row.fetchOne(
            db, sql: "SELECT * FROM tracks WHERE identity_key = ?", arguments: [item.identityKey]
        )
        let track = item.track
        try db.execute(
            sql: SQL.upsertTrack,
            arguments: [
                track.rootID, item.identityKey, item.fileResourceID, track.relativePath, track.filename,
                track.title, track.artist, track.album, track.albumArtist, track.genre,
                track.discNumber, track.trackNumber, track.duration, track.fileSize,
                track.modifiedAt.timeIntervalSince1970, track.format, track.bitrate,
                track.hasArtwork, track.isAvailable, track.addedAt.timeIntervalSince1970, sessionID
            ]
        )
        let changed = db.changesCount
        guard let updated = try Row.fetchOne(
            db, sql: "SELECT * FROM tracks WHERE identity_key = ?", arguments: [item.identityKey]
        ) else { return changed }
        if previous == nil {
            try insertActivity(db: db, kind: .added, trackRow: updated, changes: [])
        } else {
            let changes = activityChanges(from: previous, to: updated)
            if !changes.isEmpty {
                try insertActivity(db: db, kind: .fileModified, trackRow: updated, changes: changes)
            } else if let previous, previous["is_available"] as Bool == false {
                try insertActivity(db: db, kind: .restored, trackRow: updated, changes: [])
            }
        }
        return changed
    }

    private static func activityChanges(from previous: Row?, to updated: Row) -> [LibraryActivityChange] {
        guard let previous else { return [] }
        var changes: [LibraryActivityChange] = []
        func append(_ field: String, _ oldValue: String, _ newValue: String) {
            guard oldValue != newValue else { return }
            changes.append(.init(field: field, oldValue: oldValue, newValue: newValue))
        }
        for field in ["title", "artist", "album", "album_artist", "genre", "relative_path", "filename", "format"] {
            append(field, previous[field] as String, updated[field] as String)
        }
        for field in ["disc_number", "track_number", "bitrate"] {
            let old: Int? = previous[field]
            let new: Int? = updated[field]
            append(field, old.map(String.init) ?? "", new.map(String.init) ?? "")
        }
        let oldSize: Int64 = previous["file_size"]
        let newSize: Int64 = updated["file_size"]
        append("file_size", String(oldSize), String(newSize))
        let oldModified: Double = previous["modified_at"]
        let newModified: Double = updated["modified_at"]
        append("modified_at", String(oldModified), String(newModified))
        let oldArtwork: Bool = previous["has_artwork"]
        let newArtwork: Bool = updated["has_artwork"]
        append("has_artwork", String(oldArtwork), String(newArtwork))
        return changes
    }

    private static func insertActivity(
        db: Database, kind: LibraryActivityKind, trackRow: Row,
        changes: [LibraryActivityChange]
    ) throws {
        let rootID: Int64 = trackRow["root_id"]
        let relativePath: String = trackRow["relative_path"]
        let rootPath = try String.fetchOne(
            db, sql: "SELECT last_known_path FROM scan_roots WHERE id = ?", arguments: [rootID]
        ) ?? ""
        let absolutePath = rootPath.isEmpty
            ? relativePath
            : URL(fileURLWithPath: rootPath, isDirectory: true).appending(path: relativePath).path
        let data = try JSONEncoder().encode(changes)
        let changesJSON = String(decoding: data, as: UTF8.self)
        try db.execute(
            sql: """
                INSERT INTO library_activity_log(
                    kind, track_id, root_id, relative_path, absolute_path, filename,
                    title, artist, album, changes_json, occurred_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                kind.rawValue, trackRow["id"] as Int64, rootID, relativePath, absolutePath,
                trackRow["filename"] as String, trackRow["title"] as String,
                trackRow["artist"] as String, trackRow["album"] as String,
                changesJSON, Date().timeIntervalSince1970
            ]
        )
    }

    private static func pruneActivityLog(db: Database, maximumCount: Int = 100_000) throws {
        let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM library_activity_log") ?? 0
        guard count > maximumCount else { return }
        try db.execute(
            sql: """
                DELETE FROM library_activity_log
                WHERE id IN (
                    SELECT id FROM library_activity_log
                    ORDER BY occurred_at ASC, id ASC
                    LIMIT ?
                )
                """,
            arguments: [count - maximumCount]
        )
    }

    private static func refreshDimensions(db: Database, imports: [TrackImport]) throws {
        for item in imports {
            let track = item.track
            if !track.artist.isEmpty {
                try db.execute(sql: "INSERT OR IGNORE INTO artists(name) VALUES (?)", arguments: [track.artist])
            }
            if !track.album.isEmpty {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO albums(name, album_artist) VALUES (?, ?)",
                    arguments: [track.album, track.albumArtist]
                )
            }
            if !track.genre.isEmpty {
                try db.execute(sql: "INSERT OR IGNORE INTO genres(name) VALUES (?)", arguments: [track.genre])
            }
        }
    }
}

private enum SQL {
    static let upsertTrack = """
        INSERT INTO tracks(
            root_id, identity_key, file_resource_id, relative_path, filename, title, artist, album,
            album_artist, genre, disc_number, track_number, duration, file_size, modified_at, format,
            bitrate, has_artwork, is_available, added_at, last_seen_session_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(identity_key) DO UPDATE SET
            root_id = excluded.root_id,
            file_resource_id = excluded.file_resource_id,
            relative_path = excluded.relative_path,
            filename = excluded.filename,
            title = excluded.title,
            artist = excluded.artist,
            album = excluded.album,
            album_artist = excluded.album_artist,
            genre = excluded.genre,
            disc_number = excluded.disc_number,
            track_number = excluded.track_number,
            duration = excluded.duration,
            file_size = excluded.file_size,
            modified_at = excluded.modified_at,
            format = excluded.format,
            bitrate = excluded.bitrate,
            has_artwork = excluded.has_artwork,
            is_available = excluded.is_available,
            last_seen_session_id = excluded.last_seen_session_id
        """
}

private enum Schema {
    static let libraryActivityLog = """
        CREATE TABLE library_activity_log(
            id INTEGER PRIMARY KEY,
            kind TEXT NOT NULL,
            track_id INTEGER,
            root_id INTEGER NOT NULL,
            relative_path TEXT NOT NULL,
            absolute_path TEXT NOT NULL,
            filename TEXT NOT NULL,
            title TEXT NOT NULL,
            artist TEXT NOT NULL DEFAULT '',
            album TEXT NOT NULL DEFAULT '',
            changes_json TEXT NOT NULL DEFAULT '[]',
            occurred_at REAL NOT NULL
        );
        CREATE INDEX activity_log_time_idx ON library_activity_log(occurred_at DESC, id DESC);
        CREATE INDEX activity_log_kind_time_idx ON library_activity_log(kind, occurred_at DESC, id DESC);
        CREATE INDEX activity_log_track_idx ON library_activity_log(track_id, id DESC);
        """

    static let metadataDiagnostics = """
        CREATE TABLE metadata_terms(
            id INTEGER PRIMARY KEY,
            field TEXT NOT NULL,
            value TEXT NOT NULL,
            normalized TEXT NOT NULL,
            prefix TEXT NOT NULL,
            char_count INTEGER NOT NULL,
            track_count INTEGER NOT NULL,
            UNIQUE(field, value)
        );
        CREATE INDEX metadata_terms_normalized_idx ON metadata_terms(field, normalized, id);
        CREATE INDEX metadata_terms_prefix_idx ON metadata_terms(field, prefix, char_count, id);

        CREATE TABLE metadata_variation_candidates(
            id INTEGER PRIMARY KEY,
            field TEXT NOT NULL,
            value_a TEXT NOT NULL,
            value_b TEXT NOT NULL,
            track_count_a INTEGER NOT NULL,
            track_count_b INTEGER NOT NULL,
            reason TEXT NOT NULL,
            edit_distance INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'pending',
            created_at REAL NOT NULL,
            UNIQUE(field, value_a, value_b, reason)
        );
        CREATE INDEX metadata_candidates_status_idx ON metadata_variation_candidates(status, reason, field, id);
        """
    static let trackEditingAndExclusions = """
        CREATE TABLE excluded_tracks(
            identity_key TEXT PRIMARY KEY,
            root_id INTEGER NOT NULL,
            relative_path TEXT NOT NULL,
            removed_at REAL NOT NULL,
            file_was_trashed INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX excluded_tracks_root_path_idx ON excluded_tracks(root_id, relative_path);
        """

    static let libraryExperience = """
        ALTER TABLE tracks ADD COLUMN is_favorite INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE tracks ADD COLUMN play_count INTEGER NOT NULL DEFAULT 0;
        ALTER TABLE tracks ADD COLUMN last_played_at REAL;
        CREATE INDEX tracks_favorite_idx ON tracks(is_favorite, title COLLATE NOCASE, id);
        CREATE INDEX tracks_recent_idx ON tracks(last_played_at DESC, id DESC);

        CREATE TABLE app_settings(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE storage_destinations(
            id INTEGER PRIMARY KEY, name TEXT NOT NULL, path TEXT NOT NULL UNIQUE, bookmark BLOB NOT NULL,
            is_primary INTEGER NOT NULL DEFAULT 0, is_available INTEGER NOT NULL DEFAULT 1, created_at REAL NOT NULL
        );
        CREATE TABLE pending_imports(
            id INTEGER PRIMARY KEY, local_path TEXT NOT NULL, filename TEXT NOT NULL,
            state TEXT NOT NULL, created_at REAL NOT NULL, error_message TEXT
        );
        CREATE INDEX pending_imports_state_idx ON pending_imports(state, created_at DESC);
        CREATE TABLE local_cache(
            track_id INTEGER PRIMARY KEY REFERENCES tracks(id) ON DELETE CASCADE,
            local_path TEXT NOT NULL, file_size INTEGER NOT NULL, cached_at REAL NOT NULL, last_accessed_at REAL NOT NULL
        );
        CREATE INDEX local_cache_lru_idx ON local_cache(last_accessed_at);
        CREATE TABLE lyrics(
            track_id INTEGER PRIMARY KEY REFERENCES tracks(id) ON DELETE CASCADE,
            provider TEXT NOT NULL, plain_lyrics TEXT NOT NULL, synced_lyrics TEXT, updated_at REAL NOT NULL
        );
        CREATE TABLE web_metadata(
            id INTEGER PRIMARY KEY, entity_type TEXT NOT NULL, lookup_key TEXT NOT NULL, provider TEXT NOT NULL,
            remote_id TEXT, image_url TEXT, local_image_path TEXT, wiki_url TEXT, detected_genre TEXT,
            status TEXT NOT NULL DEFAULT 'pending', updated_at REAL NOT NULL,
            UNIQUE(entity_type, lookup_key, provider)
        );
        CREATE TABLE library_differences(
            id INTEGER PRIMARY KEY, root_id INTEGER NOT NULL, relative_path TEXT NOT NULL,
            kind TEXT NOT NULL, checked_at REAL NOT NULL, UNIQUE(root_id, relative_path, kind)
        );
        CREATE INDEX library_differences_root_kind_idx ON library_differences(root_id, kind, id);
        """

    static let playQueue = """
        CREATE TABLE play_queue(
            id INTEGER PRIMARY KEY,
            track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
            position INTEGER NOT NULL UNIQUE,
            added_at REAL NOT NULL
        );
        CREATE INDEX play_queue_order_idx ON play_queue(position, id);
        """

    static let pinnedOfflineCache = """
        ALTER TABLE local_cache ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0;
        CREATE INDEX local_cache_pinned_lru_idx ON local_cache(is_pinned, last_accessed_at DESC, track_id);
        """

    static let initial = """
        CREATE TABLE schema_migrations(
            version INTEGER PRIMARY KEY,
            applied_at REAL NOT NULL
        );

        CREATE TABLE scan_roots(
            id INTEGER PRIMARY KEY,
            display_name TEXT NOT NULL,
            bookmark BLOB NOT NULL,
            volume_uuid TEXT,
            last_known_path TEXT NOT NULL UNIQUE,
            is_available INTEGER NOT NULL DEFAULT 1,
            created_at REAL NOT NULL
        );

        CREATE TABLE scan_sessions(
            id INTEGER PRIMARY KEY,
            root_id INTEGER NOT NULL REFERENCES scan_roots(id) ON DELETE CASCADE,
            state TEXT NOT NULL,
            started_at REAL NOT NULL,
            finished_at REAL,
            resume_cursor TEXT,
            discovered INTEGER NOT NULL DEFAULT 0,
            processed INTEGER NOT NULL DEFAULT 0,
            changed_count INTEGER NOT NULL DEFAULT 0,
            skipped INTEGER NOT NULL DEFAULT 0,
            error_count INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE artists(
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL COLLATE NOCASE UNIQUE
        );
        CREATE TABLE albums(
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL COLLATE NOCASE,
            album_artist TEXT NOT NULL DEFAULT '' COLLATE NOCASE,
            UNIQUE(name, album_artist)
        );
        CREATE TABLE genres(
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL COLLATE NOCASE UNIQUE
        );

        CREATE TABLE tracks(
            id INTEGER PRIMARY KEY,
            root_id INTEGER NOT NULL,
            identity_key TEXT NOT NULL UNIQUE,
            file_resource_id TEXT,
            relative_path TEXT NOT NULL,
            filename TEXT NOT NULL,
            title TEXT NOT NULL,
            artist TEXT NOT NULL DEFAULT '',
            album TEXT NOT NULL DEFAULT '',
            album_artist TEXT NOT NULL DEFAULT '',
            genre TEXT NOT NULL DEFAULT '',
            disc_number INTEGER,
            track_number INTEGER,
            duration REAL NOT NULL DEFAULT 0,
            file_size INTEGER NOT NULL,
            modified_at REAL NOT NULL,
            format TEXT NOT NULL,
            bitrate INTEGER,
            has_artwork INTEGER NOT NULL DEFAULT 0,
            is_available INTEGER NOT NULL DEFAULT 1,
            added_at REAL NOT NULL,
            last_seen_session_id INTEGER,
            UNIQUE(root_id, relative_path)
        );
        CREATE INDEX tracks_title_idx ON tracks(title COLLATE NOCASE, id);
        CREATE INDEX tracks_artist_idx ON tracks(artist COLLATE NOCASE, album COLLATE NOCASE, id);
        CREATE INDEX tracks_album_idx ON tracks(album COLLATE NOCASE, disc_number, track_number, id);
        CREATE INDEX tracks_added_idx ON tracks(added_at DESC, id DESC);
        CREATE INDEX tracks_path_idx ON tracks(relative_path COLLATE NOCASE, id);
        CREATE INDEX tracks_root_seen_idx ON tracks(root_id, last_seen_session_id);
        CREATE INDEX tracks_available_id_idx ON tracks(is_available, id);

        CREATE VIRTUAL TABLE tracks_fts USING fts5(
            title, artist, album, genre, filename,
            content='tracks', content_rowid='id',
            tokenize='unicode61 remove_diacritics 2'
        );
        CREATE TRIGGER tracks_ai AFTER INSERT ON tracks BEGIN
            INSERT INTO tracks_fts(rowid, title, artist, album, genre, filename)
            VALUES (new.id, new.title, new.artist, new.album, new.genre, new.filename);
        END;
        CREATE TRIGGER tracks_ad AFTER DELETE ON tracks BEGIN
            INSERT INTO tracks_fts(tracks_fts, rowid, title, artist, album, genre, filename)
            VALUES ('delete', old.id, old.title, old.artist, old.album, old.genre, old.filename);
        END;
        CREATE TRIGGER tracks_au AFTER UPDATE ON tracks BEGIN
            INSERT INTO tracks_fts(tracks_fts, rowid, title, artist, album, genre, filename)
            VALUES ('delete', old.id, old.title, old.artist, old.album, old.genre, old.filename);
            INSERT INTO tracks_fts(rowid, title, artist, album, genre, filename)
            VALUES (new.id, new.title, new.artist, new.album, new.genre, new.filename);
        END;

        CREATE TABLE playlists(
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL COLLATE NOCASE UNIQUE,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        );
        CREATE TABLE playlist_items(
            id INTEGER PRIMARY KEY,
            playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
            track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
            position INTEGER NOT NULL,
            created_at REAL NOT NULL,
            UNIQUE(playlist_id, track_id),
            UNIQUE(playlist_id, position)
        );
        CREATE INDEX playlist_items_order_idx ON playlist_items(playlist_id, position);

        CREATE TABLE scan_errors(
            id INTEGER PRIMARY KEY,
            session_id INTEGER NOT NULL REFERENCES scan_sessions(id) ON DELETE CASCADE,
            path TEXT NOT NULL,
            message TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        CREATE INDEX scan_errors_session_idx ON scan_errors(session_id, id);
        """
}
