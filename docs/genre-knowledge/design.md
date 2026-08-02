# Genre Canonicalization and Knowledge Design

## Evidence

- The [Lazyweb genre-browse report](https://www.lazyweb.com/report/lazyweb/aabeca7b-6874-4f37-80d2-712b44209c61/?source=create) shows that music browse screens keep category rows scannable, while AllMusic-style genre pages move history and characteristics into a detail surface.
- The current SwiftUI screen already follows this hierarchy with a one-line row description and a selected-genre detail header. The implementation should enrich those surfaces instead of making every row dense.
- MediaWiki's official REST API supports page search and cross-language page links. Vibe will use the Japanese page to locate the corresponding English title, then fetch attributed summaries for both languages.

## Root cause

`GenreNormalizer.normalize` returns the original label whenever Japanese characters remain after its static replacements. This is a deliberate safety guard, but the background job records no unresolved total and clears its progress when it finishes. Therefore an enabled/idle label can coexist with untranslated genres and appear broken.

## Data model

Add `genre_knowledge` in schema migration v12:

- `raw_key`: normalized case-insensitive lookup key, primary key
- `raw_genre`: original label
- `canonical_name`: English canonical label
- `summary_ja`, `summary_en`: attributed summaries
- `source_title`, `source_url`: provenance
- `resolved_at`: cache timestamp

The table is small because it scales with unique genre aliases rather than tracks.

## Resolution flow

1. Apply the bundled normalizer.
2. If the result contains no Japanese characters, use it immediately.
3. Check `genre_knowledge` for the raw lookup key.
4. Search Japanese Wikipedia for the raw label plus music context.
5. Require a music-related candidate and its English language link.
6. Normalize the English page title into the canonical label.
7. Fetch Japanese and English summaries and save them with the source URL.
8. Apply the canonical label through the existing file-write or pending-edit path.
9. On any ambiguity or network failure, preserve the original and increment unresolved count.

## UI

- Genre rows: canonical English name, one-line cached summary, track count.
- Selected genre: detailed cached summary plus `Wikipedia` source link; fall back to the bundled description catalog while a source is unavailable.
- Management status: running progress includes checked/updated/unresolved; completed state retains its last totals and timestamp instead of reverting to only “on”.

## Safety and privacy

- Send only the genre label to Wikipedia. Do not send track titles, paths, API keys, or audio.
- Do not write the production database in tests.
- Preserve ID3v2.2 confirmation/repair rules and offline pending edits.
- Cache only successful, attributable resolutions; ambiguous results remain unresolved.

## Lazyweb influence

The evidence favors progressive disclosure: keep the list at two text lines and place provenance and longer content in the selected-genre detail. It also favors explicit status text over a passive enabled indicator for long-running maintenance.
