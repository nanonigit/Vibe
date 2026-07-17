# MassiveMusic v0.2 Findings

## Requirements

- Stage newly added music locally, then ask later whether to move it to the selected destination.
- Show differences between registered tracks and files present on storage.
- Add a music-player-style Dock icon.
- Fetch/cache album and artist imagery from the web.
- Add favorites and a Favorites library view.
- Make storage destination configurable and clearly show disconnected destinations.
- Display/cache lyrics and related imagery.
- Add a switchable mini-player.
- Add configurable recent-track or recent-album local caching.
- Enrich genre automatically when possible.
- Show album/song Wikipedia pages internally.
- Recommend similar local music.
- Surface artist news.
- Make every feature's Pending/In progress/Done state visible.
- Track columns must sort from the clicked header and toggle ascending/descending.
- UI language must switch between Japanese and English; Wikipedia/news should request the selected language and translate externally sourced text when needed.
- Appearance must support System, Light and Dark.
- Album rows need artist and track count; artist rows need album and track counts; both need drill-down links.

## v0.3 Constraints

- Sorting must remain SQL/keyset-based. SwiftUI must never sort the 370,270-track library in memory.
- Album/artist summaries must be grouped and paged in SQLite, with indexes supporting the grouping predicates.
- Runtime language selection requires an app-owned localization layer because changing `Locale` alone does not re-evaluate hard-coded Japanese strings.
- Wikipedia and Google News can be requested in the selected locale; arbitrary third-party article translation requires a translation provider and cannot be promised as an offline/local operation.

## Existing Baseline

- Production library contains 370,270 tracks and passed SQLite quick_check.
- App uses SwiftUI, GRDB/SQLite FTS5, AVFoundation, security-scoped bookmarks and bounded 200-row pages.
- Production DB is inside the sandbox container; source audio is on `/Volumes/Transcend/Music/Music`.
- The generated Xcode project currently has no app icon asset catalog and only read-only selected-file/bookmark sandbox entitlements.

## Technical Decisions

| Decision | Rationale |
|---|---|
| Use app-managed Application Support/Inbox for imports | Durable local staging, independent of SSD availability |
| Store only provider URLs/IDs and bounded cached files | Avoid bloating SQLite and permit cache eviction |
| Keep web enrichment opt-in/configurable and background-only | Playback and browsing must remain usable offline |
| Use Wikimedia/MusicBrainz ecosystem where terms permit | Open metadata with documented APIs and attribution paths |
| Treat lyrics as a provider abstraction with provenance | Lyrics licensing differs by source; do not hard-wire unsafe scraping |

## Research Findings

- Lazyweb desktop music references consistently use a persistent library sidebar, a dense central track/list area, artwork-led detail/discovery surfaces, and a playback bar that stays available while browsing.
- Offline/download state is shown next to the affected music or destination rather than hidden in settings.
- Mini players keep only artwork, title/artist, transport, seek and volume; enrichment content belongs in the full window.
- Pending: authoritative provider/API validation.

## Issues Encountered

| Issue | Resolution |
|---|---|
| Initial inspection used a stale `MassiveMusic/` path prefix | Confirmed the repository root directly contains `Sources/`, `Tests/`, and `project.yml`; all subsequent edits use those paths |

## Visual/Browser Findings

- Current MassiveMusic screenshot captured at `/var/folders/b0/c61d4nmx6j5c5gt_13zf4n740000gq/T/codex-shot-2026-07-16_08-23-40.png` for Lazyweb's optimization report.
- Existing UI already has the correct large-library shell; v0.2 should add a right-side contextual inspector and separate settings/status surfaces instead of widening the bottom playback bar.
- Lazyweb optimization report job `13a20d2a-f4f1-44eb-a39e-a5b68ce9b598` started from the current app screenshot.
- Lazyweb completed the non-degraded UI report: `https://www.lazyweb.com/report/lazyweb/1d47a8f6-b080-4555-9695-db4975fe9983/?source=create`.
- v0.3 Lazyweb search (`desktop music album artist library`) found strong matches. Relevant patterns are: sortable dense tables for the all-tracks view, album detail headers with artwork/title/artist plus a tracklist, and artist views that expose album collections before drilling into songs.
- The supplied screenshots confirm the current album/artist facet view only renders a name and a count; it has no semantic entity row, selection path, or sort indicator.
- The v0.3 Lazyweb hosted report is running as job `33fd672d-5b45-4d37-8610-b2477137b36a` from the supplied album screenshot.
- The v0.3 Lazyweb report completed without degradation: `https://www.lazyweb.com/report/lazyweb/a97cf62d-187b-46b5-a890-2b9c131ba4d5/?source=create`.
- Production read-only measurements: first 200 grouped albums ~1.49 s, first 200 grouped artists ~0.30 s, about 22 MB query-process RSS. Both run off the MainActor and return bounded pages.

## Code Inspection

- The current database has only the v1 migration. v0.2 must use additive migrations so the verified 370,270-track production database is preserved.
- `Track` has no favorite, playback-history, local-cache, or web-enrichment fields yet.
- `LibrarySection` currently covers tracks, albums, artists, genres, playlists, and folders. Favorites, Inbox, differences, settings, and implementation status need new navigation routes.
- `MassiveMusicApp` currently exposes one `WindowGroup`; a compact player can be added as a second window sharing the same playback environment.
- Sandbox configuration currently grants read-only access to user-selected files. Explicitly confirmed destination moves require user-selected read/write access; web metadata requires the network-client entitlement.
- No asset catalog/AppIcon build setting exists yet.
- Playback currently resolves only the security-scoped scan root and streams the original file. Offline-cache resolution must be checked before opening the root, while keeping the root as fallback.
- Existing `ArtworkCache` already bounds embedded-art memory to 64 MB and disk to 2 GB. Web artwork should extend this cache rather than creating an unbounded second cache.
- A new 1024px opaque app icon was generated at `/Users/naoki/.codex/generated_images/019f6836-ef15-7730-8b4e-5c6d71dc742e/exec-ed149dd8-5988-4c7d-b74b-d696d87867a9.png`.
- Final Release bundle contains compiled `AppIcon` renditions, is arm64-native, and runs against the migrated production DB.
- `TrackSort` currently assumes one fixed direction per field, and keyset predicates are hard-coded to `>` (except added date). Direction must be passed through `orderSQL` and `cursorPredicate` together to avoid skipped/duplicated pages.
- Album/artist views currently use the generic `Facet` query and estimate totals as 201 for a full 200-row page. Dedicated summary-page models/queries are required for accurate entity totals and drill-down.
- Current user-facing strings are hard-coded Japanese across `ContentView`, settings, dialogs and drive errors. Runtime locale switching therefore needs explicit app-owned translation rather than only `.environment(\.locale, ...)`.
- Web enrichment hard-codes `ja.wikipedia.org` and Japanese Google News parameters; both can be selected by the stored app language before network requests.
- The first v0.3 compile confirmed `.tableColumnHeaders(.hidden)` is available on the target SDK, so a custom aligned header can provide deterministic SQL sort buttons without letting SwiftUI reorder the 200-row page in memory.
- Artist counts are refreshed from SQLite when navigating from a song/album link, so drill-down headers remain exact even when the originating row did not carry aggregate counts.
# Phase 8 findings

- The requested destructive operation has two different scopes and needs separate labels: hide from the app library, or move the source file to the macOS Trash.
- Lazyweb examples consistently use a short confirmation dialog with Cancel plus an explicitly named destructive action; recoverability should be stated when Trash is used.
- Production verification must not edit or delete any of the 370k indexed source files. Metadata writes and Trash behavior will be tested only against copied fixtures.
- Existing security-scoped bookmarks were created read-only even though the sandbox entitlement allows read/write. New bookmarks now request read/write; existing roots are re-authorized on demand before a file mutation.
- AudioToolbox metadata writes succeeded on copied MP3 and M4A fixtures. Standard RIFF/WAV rejected the generic info-dictionary setter, so WAV now uses a bounded RIFF LIST/INFO writer and verifies the PCM byte region remains present.
- Lazyweb report for the edit/delete interaction: https://www.lazyweb.com/report/lazyweb/eb483b25-be05-4b32-8d32-02597be80771/?source=create
# Phase 9 findings

- No MassiveMusic-specific prior memory entry exists; current workspace and production DB remain the authority.
- Exact issue classes should be database-filtered and paged: missing title/artist/album and MP3 metadata containing URL-like tokens.
- Variation detection must not materialize 370k tracks. Persist distinct terms and candidate pairs in SQLite, populate them in chunks, and review only bounded candidates per normalization bucket.
- “Likely typo” is inherently heuristic, so the UI must display the reason/confidence and keep it separate from deterministic width/space/case variants.
- Read-only production counts currently show 0 stored empty titles, 61 empty artists, 96 empty albums, and 28 MP3 rows with URL-like metadata. Titles are never empty today because the scanner deliberately falls back to the filename when a title tag is absent.
- Lazyweb references support a desktop split between a compact category/status summary and a detailed review list; the evidence was only moderately close, so MassiveMusic should keep native list/table conventions rather than copy a streaming screen.
- Empty artist values must remain empty in the DB/tag for diagnostics, while the artist browser maps the empty grouping to localized “Unknown Artist”. This is a logical library group, not a filesystem move.

# Phase 16 findings

- The artwork writer and production MP3 were correct: all ten matching tracks have `has_artwork = 1`, and AVFoundation successfully extracted the image from track ID 270735.
- The visible placeholder was a read-path defect. `ContentView` only received `WebEnrichmentInfo.artworkURL`, and that property was populated solely by MusicBrainz/Cover Art Archive.
- Offline audio copies can predate a later metadata edit. Embedded-artwork lookup must therefore try the offline copy, then continue to the security-scoped source when the copy contains no artwork.
- A successful artwork edit must invalidate both memory and disk thumbnails before refreshing the currently enriched track; otherwise the right pane can legitimately reuse an old placeholder or thumbnail.

# Phase 17 findings

- The app was already caching played tracks in the correct local library location, but the cache had only one LRU class and no way to retain user-requested favorites.
- Production verification found nine cache rows and nine corresponding files before migration.
- A pinned flag belongs on `local_cache`, not `tracks`: it describes the lifecycle of a local copy and lets Favorites remain a dynamic library view.
- Normal playback access must preserve an existing pin. The cache upsert therefore only promotes `is_pinned` and never clears it implicitly.
- Checking the scan root before the cache made offline playback impossible despite a valid local copy. Cache-first URL resolution removes that unnecessary SSD dependency.

# Phase 18 findings

- The existing generic `isLoading` flag only covered database work, so it could not explain the debounce interval after typing. A separate `isSearchPending` state makes the entire search lifecycle visible without treating unrelated page loads as searches.
- The searching indicator is conditioned on a nonempty query; clearing hides it immediately while the normal page-loading overlay can continue to describe the unfiltered reload.

# Phase 19 findings

- MusicBrainz recording search responses include the linked release, medium position, and a release-specific `track` entry, so album, disc, and track numbers can be derived without a second lookup for each candidate.
- A recording can appear on many releases. Blindly accepting the first result can choose a compilation or video release, so candidate ranking and visible confirmation are required before a source file is changed.
- Adding the existing album as a `release:` search term substantially improves edition selection. Because existing tags may be wrong, an empty result automatically falls back to title-and-artist search.
- The app keeps the final write behind the existing working-copy verification and rollback path; Web data only populates editable fields.

# Phase 20 findings

- The played-song and favorite cache already had the correct storage directory and cache-first playback behavior. A separate cache implementation would have produced conflicting eviction and offline-availability rules, so the new Library view uses the same `local_cache` table and `OfflineCacheManager`.
- Cached-song browsing needs its own paged SQL query; deriving the view by testing all 370,270 tracks on the filesystem would violate the large-library memory and latency requirements.
- Explicit right-click caching is a normal recent cache entry, so the configured song limit remains meaningful. Favorite copies explicitly saved locally retain their existing pinned behavior and are excluded from LRU eviction.
- Removing a cache entry deletes only the Application Support copy and its `local_cache` row. It never deletes or edits the registered SSD source.
