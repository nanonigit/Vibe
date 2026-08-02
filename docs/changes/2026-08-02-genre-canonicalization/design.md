# Genre Canonicalization Design

## Findings before implementation

- The active checkout is the newer Codex checkout, not `/Users/naoki/Documents/Vibe`.
- Commit `6cd199ac` introduced `GenreNormalizer`, but current genre SQL still groups raw strings.
- The current fallback removes unmatched Japanese characters, which can corrupt an unknown label.
- The current normalizer has no focused unit tests.
- Several unrelated, uncommitted album-year and metadata changes are present and must be preserved.

## Design

`GenreNormalizer` owns a deterministic alias key and canonical English output. The alias key applies compatibility normalization, case folding, and separator folding. Explicit Japanese and English aliases win; unknown Japanese input is preserved instead of destructively stripped.

SQLite registers a pure `canonical_genre(value)` function for every pooled connection. Genre facets, sidebar counts, detail filters, storage summaries, and index offsets use this function, so grouping is immediately correct without rewriting 370,000 source files.

Newly imported tags and direct database genre updates are canonicalized at the database boundary. The existing explicit background metadata-normalization task remains paged and retains offline pending edits.

## UI evidence

Lazyweb references for Amazon Music and YouTube Music favor a single searchable genre directory with concise labels and counts. Vibe keeps its compact list; the data layer removes duplicate rows rather than adding more controls.
