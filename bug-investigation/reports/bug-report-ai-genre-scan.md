# AI Genre Scan Bug Report

## Symptom

The automatic scan advanced by about 500 tracks at once and registered no genres, making it appear that AI classification was not running.

## Timeline

1. The user started Automatic AI Genre Registration.
2. SQLite returned 500 missing-genre tracks.
3. The bundled classifier processed the batch synchronously.
4. The UI counter jumped by 500 while external providers were never called.

## 5 Whys

1. Why did progress jump? The counter was updated after a 500-row batch.
2. Why were no network-sized delays visible? Classification was local and synchronous.
3. Why were external providers not called? The bulk path directly instantiated `LocalGenreClassifier`.
4. Why was this misleading? The UI called the operation AI registration without distinguishing bundled rules from configured providers.
5. Why was it not caught? Source tests checked the threshold and paging but not the provider call path or per-track progress.

## Fishbone

- Logic: explicit scan used the wrong classifier.
- UI: no failed/below-threshold distinction.
- Batch processing: progress published only after 500 rows.
- Safety: no circuit breaker for a corrected remote path.
- Tests: provider selection was not asserted.

## Root Cause

`startAutomaticGenreScan()` classified a whole page using `LocalGenreClassifier` and then incremented progress by `batch.count`.
