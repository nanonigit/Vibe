# MassiveMusic v0.3 Task Plan

## Goal
Extend MassiveMusic with safe local ingest, configurable storage/cache, library-vs-disk reconciliation, favorites, web metadata, lyrics, recommendations, news/wiki, a mini player, and visible task status without risking the existing 370,270-track library.

## Current Phase
Phase 42 — metadata width normalization and library ordering (complete)

## Feature Status

| Feature | Status |
|---|---|
| Local inbox for newly added audio and deferred move confirmation | Done |
| Configurable primary destination | Done |
| App-library vs filesystem difference report | Partial: registered-but-missing count done |
| Clear disconnected-storage state | Done |
| Dock/app icon | Done |
| Favorites star and dynamic Favorites view | Done |
| Album/artist web artwork cache | Partial: album artwork done, artist-specific image pending |
| Lyrics display and cache | Done when LRCLIB has a match |
| Mini-player mode | Done |
| Recent-track/album local playback cache with limits | Partial: track limit done, album limit pending |
| Automatic genre enrichment | Partial: opt-in metadata-based AI suggestions done; acoustic inference pending |
| Wikipedia internal view | Done |
| Similar-track recommendations | Done: local metadata similarity |
| Artist news view | Partial: internal Google News search, no saved feed/notification |
| In-app implementation status screen | Done |
| Right-click metadata editing and scoped deletion | Done |
| Genre drill-down to albums, artists and songs | Done |
| Wikipedia/news inside the right pane | Done |
| OpenAI API key in macOS Keychain | Done |
| Persistent paged Up Next queue | Done |
| Similar-song listening transition | Done |
| YouTube search/video in right pane | Done |
| Always-visible draggable inspector grip | Done |
| Vertical A-Z/kana/0-9 SQLite index | Done |
| Shift/Command multi-selection and bulk metadata/artwork editing | Done |
| OpenAI/Gemini key status and automatic provider fallback | Done |
| Bottom player artwork and non-clipping safe-area layout | Done |
| Cache controls wrapping and left-aligned table reset | Done |
| Keychain checks without repeated startup authentication dialogs | Done |
| Disc and track number visible/resizable/sortable columns | Done |
| Paged file and metadata activity log | Done |
| Full-width sidebar navigation click targets | Done |

## Phases

### Phase 1: Discovery, UI evidence, API/legal constraints
- [x] Inspect current database, scanner, playback, UI, settings, and tests
- [x] Use Lazyweb before changing product UI
- [x] Verify authoritative provider APIs and usage requirements
- [x] Generate and validate an original app icon
- **Status:** complete

### Phase 2: Schema, settings, storage and reconciliation
- [x] Add non-destructive migrations for favorites, pending imports, cache records, web metadata and lyrics
- [x] Implement configurable storage destinations and local inbox
- [ ] Implement paged filesystem-vs-library difference reporting
- [x] Add disconnected destination status
- **Status:** partial (unregistered-on-disk detailed report pending)

### Phase 3: Favorites, cache, playback and mini player
- [x] Add favorites dynamic view and star actions
- [x] Add bounded recent-track local cache
- [x] Prefer cache during playback and preserve original fallback
- [x] Add mini-player window/mode
- **Status:** partial (album-count cache policy pending)

### Phase 4: Web enrichment and discovery
- [x] Add MusicBrainz/Cover Art Archive/Wikipedia clients and internal web view
- [x] Add cached album artwork and lyrics-provider abstraction
- [x] Add local similar-track recommendations and artist news search
- **Status:** partial (artist-specific images, acoustic genre inference, saved news feed pending)

### Phase 5: UI integration and visible task tracker
- [x] Add settings, difference summary, pending imports and enrichment panels
- [x] Add implementation status screen with Done/In progress/Pending states
- [x] Ensure all large collections stay paged
- **Status:** complete

### Phase 6: Migration safety, tests, build and live-library verification
- [x] Back up/check the production DB before first v0.2 launch
- [x] Run unit/integration tests
- [x] Build/sign arm64 app and launch against the existing library
- [x] Verify no source audio was changed by the migration/launch path
- **Status:** complete (full 360k synthetic performance benchmark was not rerun because the data-path/index strategy was unchanged)

### Phase 7: Sorting, localization, appearance and entity drill-down
- [x] Make track table headers switch ascending/descending SQL sort without loading all tracks
- [x] Add in-app Japanese/English selection and apply it to navigation, settings and web requests
- [x] Add System/Light/Dark appearance selection
- [x] Add paged album rows with artist and track counts, plus album detail navigation
- [x] Add paged artist rows with album and track counts, plus artist detail navigation
- [x] Build/test/sign/launch against the existing production database
- **Status:** complete

### Phase 10: Genre exploration and opt-in AI assistance
- [x] Make every genre row open paged album, artist, and song views
- [x] Keep Wikipedia and artist-news navigation inside the resizable right pane
- [x] Add OpenAI settings with API-key storage in macOS Keychain
- [x] Add metadata-only genre suggestions with confidence, rationale, and explicit apply
- [x] Add regression coverage and run the real copied-MP3 test suite
- **Status:** complete (acoustic audio classification remains deferred)

### Phase 11: Up Next and right-pane video
- [x] Persist queue entries as track IDs and order in additive schema v5
- [x] Page the queue at 100 rows and consume one row on Next/track end
- [x] Add Play Next actions to track context menus and similar-song rows
- [x] Make similar-song selection start playback and return to the listening view
- [x] Add YouTube search and playback in the existing right pane
- [x] Build, test, sign, migrate, and run the production app
- **Status:** complete

### Phase 12: Resize affordance and indexed navigation
- [x] Keep the center/right resize grip visible at all times
- [x] Expand its drag target and preserve drag capture
- [x] Add a vertically scrolling A-Z, hiragana, and numeric index
- [x] Resolve index destinations in SQLite without materializing the library
- [x] Cover title, album, and artist offsets with Latin/kana/numeric tests
- [x] Build, sign, install, and verify against the production library
- **Status:** complete

### Phase 13: Multi-selection and bulk metadata/artwork editing
- [x] Add normal, Command, Shift-range, and Command+Shift selection on the bounded current page
- [x] Add an explicit Select All Visible command without materializing the full library
- [x] Bulk edit title, artist, album, album artist, genre, disc number, and same/sequential track numbers with per-field opt-in controls
- [x] Add shared MP3 artwork replacement with file selection, clipboard Command+V paste, preview, and format gating
- [x] Process files individually with progress, cancellation, and aggregate failure reporting
- [x] Add regression tests, build/sign the arm64 Release, and verify the 10-song Shift range in the running app
- **Status:** complete

### Phase 14: Dual AI provider settings and automatic fallback
- [x] Keep an AI settings link visible regardless of whether a key is already registered
- [x] Add separate Keychain-backed OpenAI and Gemini key/model controls
- [x] Show each provider as not configured, checking, valid, or error without revealing the key
- [x] Try OpenAI first, then Gemini, then the offline built-in classifier
- [x] Preserve the previously saved key if replacing it cannot be stored
- [x] Add regression coverage and build/sign the arm64 Release
- **Status:** complete

### Phase 15: Disc and track number table columns
- [x] Add Disc Number and Track Number to the visible-column menu
- [x] Show both values as independent persisted columns with horizontal scrolling
- [x] Add draggable width controls and ascending/descending numeric sorting
- [x] Add paging/sort regression coverage and rebuild the arm64 Release
- **Status:** complete

### Phase 16: Registered artwork in the player inspector
- [x] Diagnose why an MP3 with `has_artwork = 1` still showed the placeholder
- [x] Prefer embedded artwork over web enrichment in the right pane
- [x] Fall through from a stale artwork-free offline copy to the SSD source
- [x] Invalidate bounded artwork caches and refresh the current track after an edit
- [x] Extract and decode the registered artwork from the reported production track without modifying it
- [x] Run the full test suite and rebuild/sign/launch the arm64 Release
- **Status:** complete

### Phase 17: Played-song and favorite offline cache
- [x] Confirm the existing played-song cache location and production cache contents
- [x] Prompt for local storage when a song is newly added to Favorites
- [x] Pin explicitly cached favorites outside the recent-song LRU limit
- [x] Unpin without deleting immediately when a song leaves Favorites
- [x] Resolve local audio before checking whether the SSD is connected
- [x] Show the absolute cache path and reveal it in Finder from settings
- [x] Add schema-v6 migration and pinned-cache regression coverage
- [x] Back up, migrate, verify, build, sign, and launch against the 370,270-track library
- **Status:** complete

### Phase 18: Search clear action and visible progress
- [x] Add a one-click clear button inside the search field
- [x] Show an explicit searching state during debounce and database work
- [x] Return to the unfiltered first page immediately after clearing
- [x] Run the full test suite and rebuild/sign/launch the arm64 Release
- **Status:** complete

### Phase 19: MusicBrainz album and track-number auto-fill
- [x] Research MusicBrainz recording/release/media response fields and request limits
- [x] Rank candidates using title, artist, album, duration, release status, and media format
- [x] Auto-fill album, album artist, disc number, and track number in the existing safe editor
- [x] Allow alternate-release selection and source review before writing
- [x] Add parser/ranking regression coverage and verify a live MusicBrainz response
- [x] Run the full test suite and rebuild/sign/launch the arm64 Release
- **Status:** complete

### Phase 20: Cache library and explicit per-track caching
- [x] Research desktop offline/download library patterns before changing the UI
- [x] Add a localized Cache destination to the Library sidebar
- [x] Page, search, sort, and play only tracks registered in the local cache
- [x] Expose automatic caching and the 0–500 recent-song limit inside the Cache screen
- [x] Add context-menu actions to cache an external-only song or remove only its local copy
- [x] Keep explicit copies inside the existing LRU policy and preserve pinned favorite copies
- [x] Add cache-page/status regression coverage and run the complete test suite
- [x] Build, deep-sign, and launch the arm64 Release
- **Status:** complete

### Phase 21: ID3v2.4 editing failure and damaged-tag repair
- [x] Inspect the reported SSD MP3 read-only and verify its audio stream
- [x] Reproduce the failure on a temporary copy
- [x] Identify and fix v2.4-to-v2.3 preserved-frame size conversion
- [x] Add an explicit confirmation flow for genuinely damaged ID3 tags
- [x] Preserve MP3 audio bytes and retain recoverable artwork during normal edits
- [x] Add synthetic malformed-tag, large-frame, and copied-production-fixture tests
- [x] Run all tests and build, deep-sign, and launch the arm64 Release
- **Status:** complete

### Phase 22: Paged library activity log
- [x] Add a localized Log item to the Manage section of the sidebar
- [x] Record file additions, scan-detected changes, metadata edits, unavailable/restored files, library removals, and Trash moves
- [x] Preserve path and metadata snapshots after a track row is removed
- [x] Add type filtering, text search, timestamps, changed-field details, and 200-row paging
- [x] Keep missing-file detection inside SQLite and bound retained history to the newest 100,000 entries
- [x] Add schema-v7 migration and end-to-end database regression coverage
- **Status:** complete

### Phase 23: Full-width sidebar navigation targets
- [x] Replace text-sized sidebar labels with a shared full-width row component
- [x] Use a rectangular hit target across icons, labels, counters, and trailing whitespace
- [x] Apply the behavior to Library, Manage, storage-difference, and playlist navigation rows
- [x] Add a structural regression test and run the complete suite
- **Status:** complete

### Phase 24: Shared bottom-player artwork and protected layout
- [x] Reuse the same enriched artwork source in the right inspector and bottom player
- [x] Keep the note placeholder only when no artwork can be loaded
- [x] Reserve the complete 70-point player bar inside the window safe area
- [x] Add a structural regression test and run the complete suite
- **Status:** complete

### Phase 25: Cache-page layout containment
- [x] Separate cache policy controls from the sort/search control group
- [x] Wrap cache controls to a second row before they can overflow left
- [x] Reset the horizontal table viewport when changing library context
- [x] Add a regression test and run the complete suite
- **Status:** complete

### Phase 26: Startup without Keychain access
- [x] Restore non-secret provider configuration state from SQLite without reading Keychain during startup
- [x] Avoid remote provider validation during app launch
- [x] Maintain non-secret registered/not-registered flags when keys are saved or removed
- [x] Keep interactive access for explicit connection tests and AI requests
- [x] Add regression coverage and review secret handling
- **Status:** complete

### Phase 27: Safe ID3v2.2-to-v2.3 conversion
- [x] Recognize ID3v2.2-or-earlier edit failures as explicitly repairable
- [x] Convert recoverable v2.2 text frames and PIC artwork to v2.3 frames
- [x] Rebuild older/unknown legacy tags only after validating the MPEG boundary
- [x] Preserve the MP3 audio payload byte-for-byte and roll back on failure
- [x] Verify the reported Voodoo Lounge track through a temporary copy only
- [x] Add synthetic and real-fixture regressions and deploy the arm64 Release
- **Status:** complete

## Decisions Made

| Decision | Rationale |
|---|---|
| Existing DB only receives additive migrations | Preserve the successfully imported 370,270-track library |
| New audio is copied to an internal inbox first | Avoid unconfirmed writes/moves to removable storage |
| File move requires an in-app confirmation at execution time | Moving is destructive to the source location |
| Artwork/lyrics/news clients are cached, bounded and provider-pluggable | Network services change and must not block playback |
| Similarity begins with local metadata | Works offline and avoids uploading listening history |

## Errors Encountered

| Error | Attempt | Resolution |
|---|---:|---|
| zsh icon-size loop did not split quoted pairs | 1 | Regenerated with explicit numeric sizes |
| Swift actor/autoclosure compile errors | 2 | Replaced autoclosures with explicit branches |
| Swift frontend crash on method-reference Slider binding | 1 | Replaced it with an explicit closure |
# Phase 8: Track metadata editing and scoped deletion

- [completed] Inspect the existing schema, security-scoped file access, metadata reader, and track context menu.
- [completed] Add durable exclusion records and database APIs so rescans do not silently restore removed tracks.
- [completed] Implement safe metadata writes using a temporary file, atomic replacement, and read-back verification.
- [completed] Add right-click edit/delete UI with distinct “library only” and “move file to Trash” choices.
- [completed] Add unit/integration tests using copied fixtures; never alter production music during verification.
- [completed] Build, sign, install, and verify the updated arm64 app.
# Phase 9: Metadata diagnostics

- [completed] Research desktop metadata-quality review patterns and inspect existing paged library architecture.
- [completed] Add additive schema and paged queries for missing fields and URL-contaminated MP3 metadata.
- [completed] Add a cancellable, chunked variation analyzer for width/space/case differences and likely typos.
- [completed] Add a localized Metadata Diagnostics screen with category counts, reasons, and track drill-down.
- [completed] Group empty artist tags under a localized logical “Unknown Artist” entry without changing files or tags.
- [completed] Compile and correct the diagnostics implementation.
- [completed] Add tests for normalization, typo candidates, paging, migration, and large-library safety.
- [completed] Replace the separate mini-player window with an in-place full/mini toggle and app icon.
- [completed] Remove the oversized vertical gap above track rows while retaining bounded paging and row actions.
- [completed] Add persistent drag-resizable track columns and per-column visibility controls.
- [completed] Add synchronized horizontal scrolling for widened columns.
- [completed] Replace estimated facet page totals with exact counts and add bounded direct-jump navigation.
- [completed] Fix nested sandbox permission-error detection for metadata edits and verify title/track-number writes on a copied production MP3.
- [completed] Build/sign/install arm64 Release and verify against the production DB without changing source audio.

### Phase 28: Full-cell track navigation targets
- [x] Reproduce artist/album navigation being limited to rendered text bounds
- [x] Make the full visible artist and album cell rectangles clickable
- [x] Preserve modifier-assisted multi-selection and normal row playback gestures
- [x] Add a regression test and run the complete suite
- [x] Build, sign, install, and verify the arm64 Release interactively

### Phase 29: Streaming continuation from a clicked list row
- [x] Capture the active track list's filter, sort field, and sort direction when playback starts
- [x] Advance to the following displayed track when a song ends or Next is pressed
- [x] Preserve album, genre, favorite, cache, playlist, diagnostics, and FTS-search scopes
- [x] Fetch one adjacent track with keyset SQL instead of materializing the remaining library
- [x] Keep explicit Up Next entries ahead of list continuation, then resume the original list
- [x] Add album-order, reverse-navigation, page-boundary, and UI-wiring regressions
- [x] Run the complete test suite and deploy the arm64 Release
- **Status:** complete

### Phase 30: Restore library position after detail navigation
- [x] Reproduce S-index track navigation returning to the beginning
- [x] Capture the parent list's index token, offset, paging cursor, sort, search, and selection
- [x] Restore the captured state without resetting to page zero
- [x] Support nested track, artist, album, and genre detail navigation with a bounded history
- [x] Add a regression test and run the complete suite
- [x] Build, sign, install, and verify the arm64 Release with the production library
- **Status:** complete

### Phase 31: Mini-player album artwork
- [x] Reproduce the mini player showing the application icon instead of the current album artwork
- [x] Reuse the bounded shared artwork view used by the full player and inspector
- [x] Refresh artwork when playback changes tracks while the mini player is visible
- [x] Add a regression test and run the complete suite
- [x] Build, sign, install, and verify the arm64 Release interactively
- **Status:** complete

### Phase 32: M4A metadata safety, fixed mini player, and playlist visibility
- [x] Reproduce the M4A `AudioToolbox error prm?` failure with a real AAC/M4A fixture
- [x] Replace only the M4A movie header and verify that the `mdat` audio payload is byte-identical
- [x] Disable native mini-player resizing while restoring resizing in the full player
- [x] Load playlists before the first context menu and show them as direct choices
- [x] Keep the existing bundle ID and database location while adopting the Vibe display name
- [x] Run the complete unit/integration suite and rebuild the arm64 Release
- [ ] Apply the remaining 13 M4A leading-space fixes after `/Volumes/Transcend/Music/Music` is mounted
- **Status:** complete except for the connection-dependent source-file pass

### Phase 33: Rescan stale-root recovery
- [x] Reproduce the reported `scan_sessions.root_id` foreign-key failure
- [x] Resolve the selected folder against current `scan_roots` before session insertion
- [x] Re-register a valid selected folder when the UI-supplied root ID is stale
- [x] Verify scanner behavior and database integrity without rebuilding the library
- **Status:** complete

### Phase 34: Duplicate bulk selection and deletion
- [x] Add an explicit checkbox to every row in Duplicate Tracks diagnostics
- [x] Add page-scoped Select All and Clear Selection actions with a live selected count
- [x] Add one bulk-delete action that remains disabled until at least one row is checked
- [x] Reuse the required confirmation that separates library-only removal from moving source files to Trash
- [x] Add a regression test and run the complete suite
- [x] Build, sign, and launch the updated arm64 Release
- **Status:** complete

### Phase 35: Missing-source playback status
- [x] Reflect disconnected scan roots in visible track rows without loading the full library
- [x] Keep tracks playable when a valid local cache exists
- [x] Show a persistent orange external-drive warning for tracks with neither source nor cache
- [x] Mark an individually missing source file unavailable after bounded playback resolution
- [x] Replace the generic file-open error with localized reconnect/rescan guidance
- [x] Add regressions and run the complete test suite
- [x] Build, sign, and launch the updated arm64 Release
- **Status:** complete

### Phase 36: Command-A page selection
- [x] Keep Command-A scoped to the focused track table instead of text fields
- [x] Select every track in the current bounded page without loading the full library
- [x] Preserve normal search-field Command-A behavior
- [x] Add a regression test
- [x] Run the complete suite and deploy the arm64 Release
- **Status:** complete

### Phase 37: Keep the final track above the player bar
- [x] Trace the clipped final row to the root safe-area overlay layout
- [x] Reserve a dedicated vertical region for the full player bar
- [x] Add a regression and run the complete test suite
- [x] Build, sign, launch, and visually verify the arm64 Release
- **Status:** complete

### Phase 38: Restore the library and separate external cache
- [x] Trace the empty library to an unintended second Application Support database
- [x] Reopen the populated 370,270-track container database without rebuilding it
- [x] Keep the Library section expanded so Songs, Albums, and Artists cannot disappear
- [x] Show Cache only when the primary storage is external; use local primary storage as its own cache
- [x] Limit the Cache page to rows backed by `local_cache`, using the existing paged query
- [x] Preserve the external-storage topology while the drive is disconnected
- [x] Prevent automatic source-tag cleanup from running while a scan root is unavailable
- [x] Add regressions, run the complete suite, build/sign/launch, and visually verify the arm64 Release
- **Status:** complete; the external drive is currently not mounted by macOS

### Phase 39: Import progress recovery and bounded activity log
- [x] Reproduce the stale FLAC-to-MP3 `13/14` progress state and validate all 14 source FLAC files
- [x] Process conversion, registration, cache, and storage movement one file at a time
- [x] Continue after a per-file failure and always clear import progress on every exit path
- [x] Record library, local-cache, and main-storage additions with their actual paths
- [x] Keep only the newest 1,000 activity rows and display exactly 100 rows per page
- [x] Add retention, paging, storage-event, and importer-control regressions
- [x] Run the complete suite, build/sign the arm64 Release, and launch Vibe
- **Status:** complete

### Phase 40: Complete FLAC imports and library navigation additions
- [x] Remove the post-termination FLAC conversion deadlock
- [x] Add successful imports to the target playlist incrementally
- [x] Verify the reported 13-file Deep Purple album through item 13
- [x] Make the cache retention count directly editable
- [x] Add the Recently Added icon and Date Added column
- [x] Move Up Next from the inspector to the Library sidebar
- [x] Automatically register a local genre classification during playback
- [x] Run all tests, build/sign the arm64 Release, launch, and visually verify Vibe
- **Status:** complete

### Phase 41: Register AI genre while main storage is offline
- [x] Reproduce the missing-file failure after a successful AI genre suggestion
- [x] Save the suggested genre to SQLite without requiring the original source file
- [x] Write the source audio tag only when the original file is currently available
- [x] Rename the confirmation action to describe library registration
- [x] Add an offline-source regression and run the complete test suite
- [x] Build, sign, launch, and verify the updated arm64 Release
- **Status:** complete

### Phase 42: Safe metadata proposals, diagnostics, width normalization, and library ordering
- [x] Keep MusicBrainz title, artist, and album results proposal-only
- [x] Auto-fill disc/track suggestions only when names and album track count match, with an ON/OFF setting
- [x] Fix M4A metadata updates that reject direct header rewriting by using a verified passthrough fallback
- [x] Refresh URL diagnostic counts from the exact result query and add paged mojibake candidates
- [x] Allow Library sidebar rows to be drag-reordered and persist their complete order
- [x] Add resumable 200-row width normalization for half-width kana and full-width ASCII metadata
- [x] Add a Display setting to stop and resume automatic normalization
- [x] Run the complete regression suite
- [x] Build, sign, launch, and verify the updated arm64 Release
- **Status:** complete

### Phase 43: Sequential track metadata editing
- [x] Keep a bounded snapshot of the currently displayed track order when opening the editor
- [x] Add Previous and Next controls with the current position and Command-[ / Command-] shortcuts
- [x] Save and verify the current source file before moving to the adjacent track
- [x] Keep the editor on the current track with its input intact when saving fails or needs ID3 repair
- [x] Refresh all editor fields and MusicBrainz suggestion state after navigation
- [x] Add regressions and run the complete test suite
- [x] Build, sign, launch, and verify the updated arm64 Release
- **Status:** complete

### Phase 44: Metadata diagnostics loading recovery
- [x] Capture a live process sample while the spinner is stuck
- [x] Replace the duplicate-track correlated subquery with bounded group aggregation
- [x] Compute ordinary metadata issue totals in one table pass
- [x] Cancel stale page loads and metadata-summary refresh tasks during navigation
- [x] Add regressions and run the complete test suite
- [x] Build, sign, launch, and verify the updated arm64 Release
- **Status:** complete

### Phase 45: Sidebar navigation, bounded page jumps, and safe MP3 boundary recovery
- [x] Add a visible Library reorder mode with drag handles and Up/Down controls
- [x] Rename Storage & Inbox to Storage & Imports
- [x] Open storage/import management and SSD differences as distinct settings pages
- [x] Hide relative page jumps whose destination is outside the valid page range
- [x] Recover an incorrect ID3 allocation only after validating consecutive MPEG audio frames
- [x] Continue automatic width normalization after an individual unreadable track and persist the cursor
- [x] Run the complete regression suite, build/sign the arm64 Release, and launch Vibe
- **Status:** complete

### Phase 46: Damaged ID3v2.2 frame-table recovery
- [x] Reproduce an ID3v2.2 tag whose enclosing boundary is valid but frame allocation is corrupt
- [x] Preserve readable legacy frames while rebuilding unreadable frame tables from library metadata
- [x] Verify that the MPEG audio payload remains byte-identical
- [x] Run the complete suite, rebuild/sign Vibe, and retry skipped width-normalization rows
- **Status:** complete

### Phase 47: Metadata editing and exact diagnostic navigation
- [x] Rebuild damaged ID3v2.2 tag tables while preserving the verified MPEG audio payload
- [x] Add MP3 compilation-album editing through the TCMP frame without replacing per-track artists
- [x] Redesign the batch editor into compact, clearly grouped rows
- [x] Prevent stale artist-detail headers from returning over Metadata Diagnostics
- [x] Add persistent drag-resizing to Album and Artist summary columns
- [x] Open metadata-variation links as exact field-and-value track lists
- [x] Add regressions and run the complete arm64 build and test suite
- **Status:** complete

### Phase 48: Pending interaction and discovery work
- [x] Replace the idle lyrics/error state with trending-song, YouTube, and music-news links
- [x] Persist drag-reordered track columns while retaining each column's stored width and visibility
- [x] Place Playlists above Manage and move folder/import actions out of the top toolbar
- [x] Make range selection react immediately instead of waiting for double-click recognition
- [x] Add bulk favorite/unfavorite and playlist actions for the current selection
- [x] Cancel stale page results before they can replace a newer artist/album/track destination
- [x] Reset list presentation to the top on detail, page, section, and index navigation
- [x] Make automatic genre registration opt-in and require at least 80% confidence
- [x] Preserve protected-database API-key storage and update stale Keychain wording
- [x] Add regressions, run the complete test suite, and build/sign/launch the arm64 Release
- **Status:** complete
