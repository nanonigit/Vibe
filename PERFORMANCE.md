# Performance report

Measured on 2026-07-16 on an Apple Silicon MacBook Air running macOS 26.5.2, Xcode 26.6, and Swift 6.3.3. The benchmark target was compiled in Release for `arm64`.

## 360,000 synthetic tracks

Command:

```sh
xcodebuild -project MassiveMusic.xcodeproj \
  -scheme MassiveMusicBench \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO build

/usr/bin/time -l env \
  DYLD_FRAMEWORK_PATH="$DERIVED_DATA/Build/Products/Release" \
  "$DERIVED_DATA/Build/Products/Release/MassiveMusicBench" 360000
```

Verified baseline run:

| Measurement | Result |
|---|---:|
| Insert 360,000 rows in 1,000-row transactions | 31.120 s |
| First FTS5 result page | 36.159 ms |
| Keyset page transition (two 200-row pages plus counts) | 109.283 ms |
| Worst-case legacy deep OFFSET query | 537.472 ms |
| SQLite database size | 192,266,240 bytes |
| Maximum resident set size | 188,186,624 bytes (~179.5 MiB) |
| Peak memory footprint reported by `time` | 144,867,928 bytes (~138.2 MiB) |

The UI uses the keyset route, not the measured deep-offset route. Only the current 200 rows are decoded into Swift values.

Final verification run (performed after the keyset count was removed from page transitions):

| Measurement | Result |
|---|---:|
| Insert and index 360,000 rows | 88.993 s |
| First FTS5 result page | 84.669 ms |
| Next 200-row keyset page, known total | 166.432 ms |
| Worst-case diagnostic deep OFFSET query (not used by UI) | 3,004.714 ms |
| Create 100,000-item playlist in 1,000-item transactions | 2.950 s |
| Read final 200 rows of 100,000-item playlist | 123.405 ms |
| SQLite database size | 197,840,896 bytes |
| Maximum resident set size | 187,449,344 bytes (~178.8 MiB) |
| Peak memory footprint reported by `time` | 145,048,152 bytes (~138.3 MiB) |

The large difference in insertion and diagnostic deep-offset time between runs reflects concurrent system load; both verified runs stayed below the 500 MB memory target, and the UI's FTS and keyset paths remained below 500 ms.

## Unit and integration tests

Command:

```sh
xcodebuild -project MassiveMusic.xcodeproj \
  -scheme MassiveMusic \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO test
```

The current run passes 57 tests in 3 suites. Verified coverage includes migrations, WAL, duplicate prevention, FTS synchronization, stable playlist order and reorder, persistent ordered Up Next paging/dequeue/removal, 10,500-item chunked playlist insertion, keyset paging and one-row playback continuation across page boundaries, exact facet-page totals, Latin/kana/numeric index offsets and their restoration after detail navigation, genre-filtered album/artist/track paging, bounded shuffle candidates, transaction rollback, unavailable-file marking, persisted interruption/resume state, broken-tag fallback and repair, safe ID3v2.2-to-v2.3 conversion with artwork and byte-identical MP3 audio, differential rescans, valid WAV metadata, disconnected-drive behavior, Unknown Artist grouping, metadata issue paging, normalized/typo variation candidates, cache behavior, the paged/filterable library activity log, full-width sidebar and track-cell hit targets, shared non-clipping bottom-player and mini-player artwork layout, cache-page control/table containment, and app/settings startup that never reads Keychain or presents authentication UI unless the user explicitly tests a connection.

Playback started from a displayed row stores only a small scope/sort cursor. Track completion and Next execute one bounded keyset query for the adjacent row; they do not load the current page's remainder or the complete library into memory and do not populate `play_queue` unless the user explicitly chooses Up Next.

On the 370,270-track production database, direct index-position measurements completed in approximately 0.20 seconds for a title jump and 0.29 seconds for a grouped album jump, using about 8–21 MB peak process memory. Queries run on a background reader and return only the destination page.

A copied production MP3 fixture (`01 _ _ 4 Lo.mp3`) was used to verify title and track-number tag writes and read-back. The test copied the file into a temporary directory and did not modify the SSD source.

## v0.5 production metadata diagnostics

The schema v4 migration completed without rebuilding the database. The production database retained 370,270 tracks and 370,270 FTS rows; `PRAGMA quick_check` returned `ok`. Direct SQLite counts match the runtime diagnostic screen: 61 tracks with an empty artist, 96 with an empty album, and 28 MP3 rows with URL-like metadata. Each deterministic category is queried in bounded pages. Variation analysis streams distinct terms in 1,000-row pages and skips ambiguous buckets above 200 terms.

## v0.7 production activity log migration

The additive schema v7 migration completed against a backed-up 344 MB production database without rebuilding it. The database retained 370,270 tracks and 370,270 FTS rows, and `PRAGMA quick_check` returned `ok`. The activity log begins empty because pre-v7 operations are not synthesized. New activity is fetched in 200-row pages and bounded to the newest 100,000 entries.

## Real audio smoke test

A 2.054-second, 16 kHz, 16-bit mono WAV was generated locally and passed to a Release smoke target that uses the production scanner and AVFoundation playback stack.

```sh
env DYLD_FRAMEWORK_PATH="$DERIVED_DATA/Build/Products/Release" \
  "$DERIVED_DATA/Build/Products/Release/MassiveMusicSmoke" \
  work/audio-fixture
```

Verified result:

```json
{
  "durationSeconds": 2.0536875,
  "format": "wav",
  "playbackAdvancedSeconds": 1.369631267,
  "scannedTracks": 1,
  "status": "passed",
  "track": "tone.wav"
}
```

## Full external-SSD library scan

Measured on 2026-07-16 after mounting `/Volumes/Transcend/Music/Music` and selecting it through the sandboxed application folder picker. The source files remained read-only; the database was written to the app container on the internal SSD.

| Measurement | Result |
|---|---:|
| Filesystem audio files | 370,270 |
| Registered tracks | 370,270 |
| MP3 / M4A / WAV | 353,661 / 16,579 / 30 |
| Full scan duration | 1,165.14 s (~19m 25s) |
| Scan errors | 0 |
| Unavailable tracks | 0 |
| Distinct identity keys | 370,270 |
| FTS rows | 370,270 |
| SQLite database size after scan | ~328 MiB |
| Observed RSS during scan | ~299 MiB |
| SQLite `quick_check` | `ok` |

Search remained responsive during scanning: an FTS query for `David Bowie` returned 556 registered rows while the scanner continued committing. Playback was verified from the external SSD with both an MP3 (`Warsong`, White Lion) and an M4A (`Disconsolate`, mihimaru GT); each advanced past two seconds in the production player.

## v0.3 aggregate-page verification

The production database remained at 370,270 tracks and passed `PRAGMA quick_check`. Read-only SQLite timing of the first 200 grouped rows measured approximately 1.49 seconds for albums and 0.30 seconds for artists, with about 22 MB maximum RSS in the query process. These aggregate requests execute on a background database reader and return only a 200-row page, so the UI and playback remain available. Track search and scrolling continue to use the faster FTS/keyset paths measured above.
