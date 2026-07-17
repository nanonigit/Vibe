# MassiveMusic v0.2 Progress

## 2026-07-16 17:05 Disc and track number columns

- Added persisted visibility and width settings for independent Disc Number and Track Number columns.
- Added header-click numeric ascending/descending sorts backed by SQLite keyset paging.
- Added a regression test covering numeric disc/track order; 38 tests in 3 suites passed.

## 2026-07-16 17:00 Right-pane button copy cleanup

- Removed the redundant `右ペインで` / `in Right Pane` wording from the Wikipedia, news, and YouTube action buttons without changing their in-pane behavior.

## 2026-07-16 16:52 Dual AI provider release verification

- Re-ran the macOS test suite after the final Keychain replacement change: 37 tests in 3 suites passed.
- Built the arm64 Release successfully, copied it to `outputs/MassiveMusic.app`, deep re-signed the app and embedded framework together, and passed strict signature verification.
- Launched the delivered app successfully against the existing 370,270-track database; no audio files were changed.
- The existing OpenAI Keychain item triggered the normal macOS access prompt. Runtime verification deliberately denied the prompt instead of reading or exposing the saved key; the app remained running.
- Completed and opened the Lazyweb report for the AI provider settings/status UI.

## 2026-07-16 16:40 Dual AI provider settings and fallback

- Added a permanent right-pane AI settings link and compact OpenAI/Gemini status indicators.
- Added separate Keychain-backed OpenAI and Gemini key/model controls, provider links, deletion, and immediate connection tests.
- Added metadata-only OpenAI -> Gemini -> offline built-in fallback with the chosen provider and fallback reason shown in the result.
- Provider validation runs without track metadata: OpenAI lists available models and Gemini reads the configured model resource.
- Changed Keychain replacement to `SecItemUpdate` first so changing a key does not delete the previous value before the new value is stored.

## 2026-07-16 15:45 Bulk metadata and artwork editing

- Added normal, Command, Shift-range, and Command+Shift range selection to the bounded current track page; verified a first-to-tenth-row Shift selection as 10 selected songs in the running Release app.
- Added a bulk editor for artist, album, album artist, genre, and shared artwork with per-field opt-in controls.
- Added opt-in title and disc-number fields plus track numbering that can increment from a chosen starting number in bounded list order.
- Moved startup OpenAI Keychain detection off the main actor after a re-signed build exposed a synchronous Keychain wait before the first window; the library window now appears immediately while key state refreshes in the background.
- Added JPEG/PNG file selection plus clipboard-image paste through Command+V or an explicit paste button, normalized to a bounded 1600px JPEG preview.
- MP3 artwork writes replace only the ID3 APIC frame while preserving other frames and audio bytes. Mixed non-MP3 artwork selections are rejected before any write.
- Added per-file progress, cancellation, aggregate failures, and safe continuation after individual failures.
- Automated result: 37 tests across 3 suites pass, including batch field preservation, MP3 artwork replacement, database artwork state, and rollback coverage. Release arm64 build/sign/run verification passed.

## 2026-07-16 14:18 Header storage summary

- Added compact GB capacity and absolute scan-root paths below the counts on Songs, Albums, Artists, and their album/artist detail headers.
- Added bounded SQLite `SUM(file_size)` and distinct-root aggregation; no track collection is materialized and page navigation reuses the scoped result.
- Added album and artist scoped aggregation tests. The full suite now passes 36 tests across 3 suites.
- Built, signed, launched, and visually verified the arm64 Release app against the 370,270-track production library (2,787.9 GB at `/Volumes/Transcend/Music/Music`).

## 2026-07-16 14:00 Metadata write and artist article handling

- Replaced unsupported AudioToolbox MP3 property writes with verified ID3v2.3/2.4 text-frame updates that preserve artwork, unknown frames, and audio bytes.
- Added app-local working/backup copies, permission-error propagation, external-volume signing access, and explicit mismatch diagnostics.
- Changed and restored the real `01 _ _ 4 Lo.mp3` title through the signed sandboxed app; restored the pre-test bytes and confirmed the original SHA-256 `e3b9a88661359f483b68541e1efe90505d54a4ca9b08f9fee367992b159969d9`.
- Removed the redundant sort picker and direction control from the Songs screen; column-header sorting remains.
- Artist search, ordering, and index offsets now ignore a leading case-insensitive `The ` while preserving displayed names.
- Final automated result: 35 tests across 3 suites pass; Release arm64 build and deep signature verification pass.

## Session: 2026-07-16

### Phase 7: Sorting, localization, appearance and drill-down
- **Status:** complete
- Actions taken:
  - Parsed the new requirements and screenshot evidence.
  - Re-opened the persistent plan under the planning-with-files workflow.
  - Ran a new Lazyweb reference search for album/artist library drill-down patterns.
  - Uploaded the supplied album screenshot and started the v0.3 hosted UI report.
  - Added bidirectional keyset sorting, album/artist summary queries, drill-down state, language-aware web requests, and System/Light/Dark settings.
  - Added regression tests for descending keyset pages and album/artist aggregates; 16 tests passed.
  - Completed the Lazyweb report and opened it in the browser.
  - Measured the paged aggregate queries read-only against the 370,270-track production DB.
  - Built, ad-hoc signed and launched the final arm64 Release bundle from `outputs/MassiveMusic.app`.
  - Used the screenshot workflow to catch and correct the missing album-detail track count, then verified album and artist drill-down through macOS Accessibility.
  - Verified runtime Japanese/English and Dark/Light switching; restored the user's Japanese/Dark settings afterward.

### Phase 1: Discovery, UI evidence, API/legal constraints
- **Status:** complete
- Actions taken:
  - Captured the user's requested features as independently trackable work items.
  - Chose an additive-migration strategy to preserve the production library.
  - Loaded planning-with-files and imagegen instructions.
  - Ran Lazyweb desktop music-library/mini-player research.
  - Captured and uploaded the current MassiveMusic screen and started the hosted UI optimization report.
  - Added the v2 additive schema and data APIs for favorites, playback history, configurable destinations, local Inbox, lyrics, web metadata, offline cache, and library differences.
  - Generated the new music-player app icon and prepared bounded macOS icon renditions.
  - Added the right-side Now Playing inspector, lyrics/discovery/info tabs, internal browser, settings/status UI, and mini-player window.
  - Unit test run passed: 14 tests in 2 suites.
- Files created/modified:
  - `task_plan.md`
  - `findings.md`
  - `progress.md`

## Test Results

| Test | Expected | Actual | Status |
|---|---|---|---|
| Existing production DB baseline | 370,270 tracks, quick_check ok | Previously verified | Pass |
| v0.2 unit tests | All tests pass | 14 tests / 2 suites passed | Pass |
| v0.3 unit tests | Sorting and aggregate regressions pass | 16 tests / 2 suites passed | Pass |
| v0.3 Release arm64 build | Native Apple Silicon app | Build succeeded; signed bundle is arm64 | Pass |
| Production v0.3 integrity | Preserve tracks/FTS and availability | 370,270 tracks, 370,270 FTS, 0 unavailable, quick_check ok | Pass |
| Runtime localization/appearance | Japanese/English and Dark/Light apply immediately | Verified both modes; restored Japanese/Dark | Pass |
| Runtime entity navigation | Counts and drill-down work | Album 11 tracks; artist 1 album/10 tracks verified | Pass |
| Release arm64 build | Native Apple Silicon app | `Mach-O 64-bit executable arm64` | Pass |
| Production migration | Preserve tracks and FTS, quick_check ok | 370,270 tracks, schema v2, FTS 370,270, quick_check ok | Pass |
| Safety backup | Pre-migration SQLite backup | 328 MB online backup created | Pass |
| App icon catalog | All macOS renditions compiled | Assets.car contains AppIcon renditions; 1024 source validated | Pass |
| Running delivery | Signed arm64 app starts on production DB | PID verified from `outputs/MassiveMusic.app` | Pass |
| v0.4 unit/integration tests | Metadata, exclusion, FTS and WAV preservation regressions | 20 tests / 3 suites passed | Pass |
| MP3/M4A metadata copies | Write and read back copied SSD fixtures | Both formats passed; source files untouched | Pass |
| Production v0.4 migration | Additive schema v3, preserve library | 370,270 tracks/FTS, 0 exclusions, quick_check ok | Pass |
| v0.4 context UI | Editor and two-scope deletion dialog | Accessibility verified; Cancel used, no production mutation | Pass |

## Error Log

| Timestamp | Error | Attempt | Resolution |
|---|---|---:|---|
| — | None yet | 1 | — |
| 08:30 | zsh did not split quoted size pairs for the first `sips` loop | 1 | Re-ran with an explicit numeric-size loop; all icon sizes generated |
| 08:33 | Swift 6 rejected actor property access inside a nil-coalescing autoclosure | 1 | Replaced the fallback with `FileManager.default` so initialization is nonisolated-safe |
| 08:35 | Swift does not allow `await` on the right side of `??` | 1 | Expanded cached-or-fetch lyrics logic into an explicit `if let` branch |
| 08:36 | Swift 6.3 frontend crashed during IR generation for a method-reference Slider binding | 1 | Replaced the method reference with an explicit closure to avoid the compiler bug |
| 08:41 | XcodeGen ignored the scalar `resources` key, so Assets.car was absent | 1 | Added the asset catalog as an explicit source with `buildPhase: resources` |
| 08:42 | Generated icon source was 1254px while the catalog slot requires 1024px | 1 | Resampled to an exact 1024x1024 source; final asset build has no icon warning |
| 08:55 | `orderSQL` ceased being a single-expression function after adding the direction local | 1 | Added an explicit `return switch` |
| 08:59 | Swift 6 rejected a MainActor localization call inside `Task.detached` | 1 | Resolve the localized playlist name before entering the detached DB task |
| 09:00 | Swift string interpolation does not accept SwiftUI's `format:` syntax outside `Text` | 1 | Format scan speed with `String(format:)` before localization |
| 09:06 | Runtime screenshot showed the custom table header vertically displaced by unused space | 1 | Expand the track-table container and pin its content to the top edge |
| 09:08 | SwiftUI `Table` retained a large internal gap even after its container was top-aligned | 2 | Render the bounded 200-row page with an aligned `List`; database paging and SQL sorting are unchanged |
| 09:11 | The main library column itself remained vertically centered beside the full-height inspector | 3 | Make the complete library column fill the detail height and align its contents to the top |
| 09:22 | Runtime album drill-down showed the artist but omitted the requested track count in its header | 1 | Display the paged album query's exact total beside the clickable artist |
| 16:05 | The first copied Release bundle exited because the app and embedded MassiveMusicCore framework had different local signing identities | 1 | Re-signed the complete bundle and embedded framework together with the production entitlements; deep verification passes and corrected PID 21925 runs normally |

## 5-Question Reboot Check

| Question | Answer |
|---|---|
| Where am I? | Phase 1 discovery/provider validation |
| Where am I going? | Storage/schema, playback/cache, web enrichment, UI, verification |
| What's the goal? | Ship MassiveMusic v0.2 safely on the existing large library |
| What have I learned? | See `findings.md` |
| What have I done? | Captured requirements and persistent plan |
# Phase 8 progress

- Started metadata editing and scoped deletion work.
- Reviewed the supplied right-click-menu screenshot and gathered Lazyweb interaction references.
- Next: inspect current database/file-access paths, then implement schema, service, and UI changes.
- Added schema v3 with exclusion tombstones, transactional library removal, FTS-synchronized metadata updates, and rescan exclusion checks.
- Added temporary-copy metadata writes and read-back verification for MP3/M4A, plus a direct RIFF INFO writer for WAV.
- Added right-click Edit Song Info and Delete actions, localized editor, two-scope deletion confirmation, and write-authorization renewal.
- Automated result: 20 tests across 3 suites pass, including metadata/FTS, exclusion persistence, WAV audio preservation, scanner, playlist, and migration coverage.
- Completed Release arm64 build, production DB migration check, install/run, and non-mutating UI interaction verification.
- Release arm64 bundle was signed with sandbox read/write bookmark entitlements and launched from `outputs/MassiveMusic.app`.
- Production schema v3 migration preserved 370,270 tracks and FTS rows; excluded count remained 0 and `quick_check` returned `ok`.
- Runtime UI verification opened the metadata sheet and the two-scope deletion dialog, then cancelled both. Production files and rows were unchanged.
# Phase 9 progress

- Started metadata diagnostics work.
- Defined three diagnostic families: missing core fields, URL-contaminated MP3 tags, and suspected duplicate spellings.
- Chose an additive SQLite-backed analyzer so the large library is never copied into one Swift array.
- Measured the actual deterministic issue counts read-only and inspected the current paged view-model routing.
- Completed the required Lazyweb reference search; a hosted optimization report will be generated after the first diagnostic screen is runnable.
- Added the follow-up requirement for a clickable Unknown Artist grouping backed by genuinely empty artist values.
- Implemented the logical Unknown Artist group while preserving empty source tags; opening it pages all matching tracks.
- Added the localized metadata diagnostics screen and bounded streaming variation analysis.
- First Debug build found the newly added analyzer file was not yet included in the generated Xcode project; regenerate before retrying.
- Debug build succeeded after Xcode project regeneration; first full test build found an ambiguous CGFloat constant in the new window-resize code.
- Replaced the second mini-player window with an in-place full/mini window mode and added the app icon plus expand control to the mini view.
- First 23-test run exposed a missing SQL table alias in Unknown Artist paging and duplicate fixture paths in the new analyzer test; both test defects were corrected.
- Replaced SwiftUI List with a bounded LazyVStack for track pages, then fixed the remaining vertical-centering behavior by giving the table an explicit GeometryReader-sized viewport.
- Final runtime verification confirmed the column header and first song row now sit directly below the search/header area with no oversized vertical gap.
- Installed and launched the signed arm64 Release bundle; production schema v4 retained 370,270 tracks/FTS rows and passed quick_check.
- Added draggable column separators for title, artist, album, and duration, plus a persistent Columns menu controlling title/artist/album/duration/format visibility.
- Rebuilt, signed, launched, and verified the final arm64 Release; all 23 tests still pass.
- Added exact aggregate counts for genre/folder pagination, bounded milestone page links, and direct page jumps without materializing all pages.
- The first new facet-count assertion used an outdated synthetic genre cardinality (32); the fixture currently generates 40 and the assertion was corrected.
- Diagnosed the reported MP3 edit failure as a sandbox write-authorization error on the temporary sibling copy; Unix permissions and the APFS mount are writable.
- Expanded authorization retry detection to nested Cocoa and POSIX permission errors and added a clear no-source-changes failure message.
- Verified title plus track-number writing/read-back using a temporary copy of the reported production MP3; all 24 tests pass and the SSD source was untouched.

# Phase 10 progress

- Added case-insensitive, SQLite-paged genre drill-down for albums, artists, and songs; no genre view materializes the full library.
- Replaced the separate internal-browser sheet with an embedded browser in the resizable right pane for Wikipedia and artist news.
- Added optional OpenAI genre suggestions based only on track metadata, with API keys stored in macOS Keychain and no automatic tag mutation.
- Added confidence/rationale review and an explicit Apply to File action using the existing authorized temporary-copy metadata writer.
- Added a genre paging regression test. All 25 tests in 3 suites pass, including the copied production MP3 write/read-back fixture.
- Completed the Lazyweb desktop music genre-browser report and opened it for review.

# Phase 11 progress

- Added schema v5 with a persistent ordered play queue that stores only track IDs, order, and timestamp.
- Added a 100-row paged Up Next inspector, per-track play/remove, clear, previous/next page, and context-menu/Discover additions.
- Next and track-end playback consume one explicit queued row before falling back to adjacent or bounded-shuffle selection.
- Similar-song clicks now start that song and return the inspector to the listening/lyrics view.
- Added YouTube search and video navigation inside the same right pane.
- All 26 tests pass; signed Release is arm64. Production migrated additively to schema v5 with 370,270 tracks/FTS rows and `quick_check=ok`.

# Metadata write permission follow-up

- Reproduced the reported permission path in code review: the retry saved a renewed bookmark, then discarded the live security scope before retrying.
- Changed metadata editing and Trash operations to retain the exact scope returned by the folder picker through temporary-copy creation, verification, and final replacement.
- Re-ran all 26 tests with the correct `MASSIVEMUSIC_METADATA_FIXTURE` variable; the copied SSD MP3 title and track-number write/read-back test executed and passed. The SSD source remained unchanged.
- Rebuilt, signed, installed, and launched the arm64 Release app.

# Phase 12 progress

- Replaced the transient 9px inspector separator with an always-visible grip and an 18px drag target; hover/drag state is emphasized and double-click resets the width.
- Added a vertically scrollable A–Z, full hiragana, and 0–9 index to songs, albums, artists, and their genre/detail variants.
- Index clicks calculate a SQLite offset and fetch only the destination page; the 370,270-row library is never materialized in memory.
- Added Latin/kana/numeric offset regression coverage. All 27 tests pass, including the real copied-SSD MP3 metadata test.
- Runtime verification jumped the live song list to B and successfully dragged the persistent inspector grip.
- Reworked large-library pagination to show a stable `-1000 -100 -10`, five-page neighborhood, and `+10 +100 +1000` sequence; out-of-range relative jumps clamp to the first or final page.
- Prevented the expanded player window from extending below the screen/Dock after mini-player switching; the window is constrained to the active screen's visible frame and the 70-point player bar keeps its full height.
- Added a direct AI-settings link from the genre empty state, automatic focus of the Keychain-backed API-key field, and an offline bundled metadata genre classifier used whenever no OpenAI key is present.
- Expanded the main player's shuffle hit target from the 15x12 glyph bounds to a visible 36x32 button, added on/off accessibility state and active styling, and aligned the neighboring repeat control.

# Phase 16 progress

- Reproduced the registered-artwork mismatch on the reported `Hog Jaw / Devil in the Details / 4 Lo` row: the production DB reports embedded artwork, while the right pane still used its placeholder.
- Traced the cause to the enrichment path, which only exposed a web-artwork URL and never asked the bounded embedded-artwork cache to read the edited audio file.
- Added embedded-artwork resolution with web fallback, cache invalidation after edits, current-track refresh, and source-file fallback when an older offline copy has no picture.
- Read-only extraction from the actual SSD MP3 produced and decoded the expected album image; no music file was changed during verification.
- Final automated result: 38 tests in 3 suites pass. The arm64 Release build succeeds, deep code-sign verification passes, and `outputs/MassiveMusic.app` is running.

# Phase 17 progress

- Confirmed the existing played-song cache already resides inside the sandboxed Application Support library and currently contains nine audio files.
- Added a three-way favorite confirmation: save locally, favorite only, or cancel. Explicitly saved favorites are pinned independently of the recent-song limit.
- Changed playback resolution to consult the local cache before resolving the SSD bookmark, allowing cached songs to play while the drive is disconnected.
- Added the absolute cache path and Finder reveal action to Offline settings.
- Added additive schema v6 and a regression test proving pinned favorites are excluded from normal LRU eviction.
- All 39 tests in 3 suites pass. Backed up the 344 MB production DB, migrated it from v5 to v6, retained 370,270 tracks and 370,270 FTS rows, and received `quick_check=ok`.
- Built, deep-signed, and launched the arm64 Release from `outputs/MassiveMusic.app`.

# Phase 18 progress

- Replaced the plain search field with an inline macOS search control containing a magnifier, one-click clear button, and accessibility labels.
- Added a dedicated pending-search state so the spinner, localized `検索中…` / `Searching…` label, and accent border cover both the 280 ms debounce and the database query.
- Clearing cancels a pending debounce and reloads the unfiltered first page immediately.
- All 39 tests in 3 suites pass. The arm64 Release build, deep-sign verification, and launch from `outputs/MassiveMusic.app` succeeded.

# Phase 19 progress

- Added MusicBrainz recording search with release/media parsing, request throttling, album-constrained lookup, and an automatic fallback without the album constraint.
- Added deterministic candidate ranking and deduplication. Exact title/artist/album, close duration, official status, and audio media are preferred; DVD/Blu-ray candidates are penalized.
- Added an auto-fill action to the song metadata editor. The best candidate fills album, album artist, disc number, and track number while retaining the existing explicit Save to File boundary.
- Added alternate-candidate selection, a direct MusicBrainz source link, progress, empty-result, and error states in Japanese and English.
- The new live-response parser test and all 40 tests in 3 suites pass. The Release build succeeds for arm64.

# Phase 20 progress

- Added a localized Cache item in the Library sidebar, backed by an exact SQLite join between `local_cache` and `tracks` with 200-row paging, FTS search, and database sorting.
- Reused the existing track table and playback controller, so double-click playback checks the local copy before resolving the SSD bookmark.
- Added in-screen controls for automatic played-song caching and the 0–500 recent-song limit. Reducing the limit immediately applies LRU eviction while preserving pinned favorite copies.
- Added per-track context actions to create a normal LRU-managed local copy or remove only the local copy. Source audio is never moved or modified.
- Added regression coverage for paged cached-song retrieval and bounded cache-status lookup. All 41 tests in 3 suites pass.

# Phase 21 progress

- Reproduced the reported `Be Yourself（Brand-New song）` failure using the actual SSD MP3 as a read-only test fixture and writing only to a temporary copy.
- Confirmed the source ID3v2.4 tag was structurally valid; the app incorrectly copied synchsafe v2.4 frame sizes into a v2.3 tag, making its own temporary output look corrupt when a large APIC artwork frame was present.
- Re-encoded preserved v2.4 frame headers during v2.3 conversion, retaining artwork and byte-identical MP3 audio.
- Added an explicit damaged-ID3 repair path that validates the MPEG boundary, rebuilds only the tag on a working copy, warns about unreadable extra fields/artwork, verifies the result, and restores the backup on failure.
- All 43 tests pass, including a large-v2.4-frame regression, a genuinely malformed-frame repair test, and the reported production MP3 copied-fixture test. The SSD source hash remained unchanged.
- Built, deep-signed, and launched the arm64 Release from `outputs/MassiveMusic.app`.

# Phase 22 progress

- Added a localized Log destination under Manage with clear status icons, timestamps, path snapshots, changed-field details, type filtering, text search, and existing 200-row page controls.
- Added additive schema v7. New scans and explicit edits record additions, file/metadata changes, unavailable/restored files, library removals, and Trash moves; no historical rows are synthesized for prior activity.
- Missing-file activity is inserted with a SQLite `INSERT … SELECT`, so a disconnected or changed large library is not materialized as a Swift array.
- Retention is bounded to the newest 100,000 entries. All 44 tests in 3 suites pass, including the complete five-event lifecycle and activity-log paging/filtering/search regression.
- Backed up the 344 MB production database, migrated it additively from v6 to v7, retained 370,270 tracks and 370,270 FTS rows, and received `quick_check=ok`. No pre-v7 history was synthesized.
- Built the arm64 Release, restored the production sandbox/bookmark/network entitlements during signing, passed deep-sign verification, and launched `outputs/MassiveMusic.app` successfully.

# Phase 23 progress

- Added one shared full-width sidebar navigation label with a rectangular content shape, so clicking the icon, title, counter, or empty area of a row invokes the same action.
- Applied it to all Library destinations, Log, Metadata Diagnostics, Storage & Inbox, Storage Differences, Feature Status, and playlists.
- Storage Differences is now an actionable row that opens Storage settings instead of being a text-only counter.
- Added a regression test for the full-width frame, rectangular hit shape, and shared-component usage. All 45 tests in 3 suites pass.
- Runtime verification clicked the trailing blank area of a Library row and confirmed that the corresponding destination opened; the arm64 Release was then signed with production entitlements and relaunched.

# Phase 24 progress

- Replaced the bottom-left permanent note placeholder with the same bounded artwork URL and rendering component used by the right inspector.
- The shared artwork view switches back to a localized-accessible note placeholder only when the current track has no usable image.
- Moved the complete 70-point bottom player into a bottom safe-area inset, preventing the library content or window edge from clipping its artwork and controls.
- Added a regression test for shared artwork usage and protected bottom layout. All 46 tests in 3 suites pass.

# Phase 25 progress

- Reproduced the cache page with its policy, sorting, column, and search controls overflowing to the left at the reported window width.
- Split cache policy controls into an adaptive row that wraps above the common library controls before either row can overlap or clip.
- Gave each track-table navigation context a distinct horizontal scroll identity, so Cache, Favorites, albums, artists, genres, and playlists open at the table's left edge instead of inheriting another page's horizontal offset.
- Added a cache-layout regression test. All 47 tests in 3 suites pass.

# Phase 26 progress

- Traced the repeated macOS password dialog to automatic OpenAI and Gemini Keychain data reads performed during every view-model initialization.
- Startup no longer calls the Security framework or reads either Keychain item. It restores only non-secret registered/not-registered flags from SQLite and does not contact provider APIs.
- Explicit Test Connections and user-requested genre classification retain interactive Keychain access, provider fallback, and validation behavior.
- API keys remain exclusively in macOS Keychain; SQLite stores only boolean registration flags, and no key value is copied to SQLite, preferences, files, errors, or logs.
- Added a regression test that verifies view-model initialization contains no Keychain refresh. All 48 tests in 3 suites pass.
- Built and ad-hoc signed the arm64 Release app with the sandbox entitlements, then opened the 370,270-track production library twice from a fully terminated state. Both launches completed without a Keychain authentication dialog.

# Phase 27 progress

- Added an explicit ID3v2.2-or-earlier conversion path that validates the declared tag boundary and the first MPEG frame before rebuilding an ID3v2.3 tag.
- Recoverable v2.2 title, artist, album, album artist, genre, track/disc numbers, and PIC artwork are converted to their v2.3 equivalents; unknown legacy frames are not fabricated.
- The existing working-copy verification and rollback path remains mandatory, so the SSD source is updated only after metadata read-back succeeds; MP3 audio is never re-encoded.
- Verified `13 Baby Break It Down.mp3` through a temporary copy only. Its converted copy retained byte-identical MP3 audio; the SSD source was not changed during verification.
- All 50 tests in 3 suites pass, including synthetic ID3v2.2 artwork/audio preservation and the reported real-file copy regression.
- Built the arm64 Release, deep-signed it with the production sandbox/bookmark entitlements, launched it from `outputs/MassiveMusic.app`, and confirmed 370,270 tracks, 370,270 FTS rows, and `quick_check=ok` in the production database.
- Runtime verification exposed a settings-level Keychain regression: opening any settings tab still invoked AI provider validation. Removed that implicit call so authentication is limited to the explicit Test Connections action; the expanded suite now passes all 51 tests in 3 suites.

# Phase 28 progress

- Reproduced track-table artist and album buttons whose visual column frames were wider than their intrinsic text-only hit regions.
- Added a shared 32-point-high navigation cell whose rectangular hit target fills the configured column width, while retaining Command/Shift selection behavior.
- Added a source-level regression test; all 52 tests in 3 suites pass.
- Built and deep-signed the arm64 Release with production entitlements, replaced `outputs/MassiveMusic.app`, and launched it successfully.
- Runtime accessibility verification clicked the empty trailing portion of an artist cell (outside its rendered text) and opened the corresponding artist page. Artist and album cells share the same full-width navigation component.

# Phase 29 progress

- A double-clicked track now starts a lightweight playback sequence containing only the active list scope, sort field, sort direction, and current cursor.
- Natural track completion and the Next button fetch the following row from that exact album, genre, favorite, cache, playlist, diagnostics, search, or main-library view.
- Adjacent-track lookup uses the same stable keyset ordering as paged display and requests only one row, including across a 200-row page boundary; it never constructs a 370,270-track Swift array or persistent queue.
- Explicit Up Next items retain priority. After they play, automatic progression resumes after the original list cursor; unrelated direct playback clears stale list context.
- Added database and source-level regressions. All 55 tests in 3 suites pass.
- Runtime verification double-clicked `Always On My Mind` in the title-sorted production library, pressed Next, and confirmed the player advanced to the immediately following displayed row, `Angels`.
- Built, deep-signed, and launched the arm64 Release from `outputs/MassiveMusic.app`; the production database retained 370,270 tracks and 370,270 FTS rows with `quick_check=ok`.

# Phase 30 progress

- Reproduced the reported S-index workflow and traced the reset to `closeDetail()` always requesting page zero.
- Added a bounded browse-return stack that preserves section, sort and direction, search, playlist/detail filters, offset, keyset cursor chain, selected rows, and the highlighted alphabet token.
- Back now restores the prior snapshot with `reset: false`; nested artist/album/genre drill-downs each retain their own parent state, while switching sidebar sections or starting a new search clears stale history.
- Moved the active alphabet token into the view model so S remains highlighted after returning instead of being erased by detail-selection changes.
- Added a source-level regression. All 56 tests in 3 suites pass.
- Runtime verification opened an artist from the indexed Songs table and pressed Back; the same rows, sort, offset, and highlighted `S` index token were restored instead of returning to page zero.

# Phase 31 progress

- Traced the incorrect mini-player image to a hard-coded `NSApplication.shared.applicationIconImage` that bypassed the library artwork pipeline.
- Replaced it with the same bounded `PlayerArtwork` component used by the inspector and bottom player, including the neutral music-note fallback when no artwork exists.
- The mini player now requests enrichment when it opens and whenever the current track changes, so embedded, cached, or downloaded album artwork updates without returning to the full window.
- Added a regression test. All 57 tests in 3 suites pass.
- Built and deep-signed the arm64 Release, then verified the production mini player with artwork-bearing tracks. The mini player displayed the actual album covers and refreshed the cover after automatic track advancement instead of showing the MassiveMusic application icon.
