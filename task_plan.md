# MassiveMusic v0.3 Task Plan

## Goal
Extend MassiveMusic with safe local ingest, configurable storage/cache, library-vs-disk reconciliation, favorites, web metadata, lyrics, recommendations, news/wiki, a mini player, and visible task status without risking the existing 370,270-track library.

## Current Phase
Phase 28 — full-cell artist and album navigation hit targets (complete)

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
