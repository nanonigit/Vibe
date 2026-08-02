# Genre Canonicalization Requirements

## Goal

Present one trustworthy, English genre taxonomy even when source tags differ by language, case, whitespace, middle dots, slashes, or hyphen variants.

## Requirements

1. The genre browser and sidebar count shall group equivalent raw tags under one canonical English name.
2. Canonicalization shall be case-insensitive and Unicode-aware and shall treat visual separator variants as aliases when they do not change meaning.
3. Japanese genre labels covered by the catalog shall map to explicit English names; unknown Japanese text shall never be silently deleted.
4. Genre detail pages shall include tracks from every raw alias in the selected canonical group.
5. New scans and manual/AI metadata writes shall store the canonical genre in the local database.
6. Existing source audio files shall not be scanned or rewritten merely to render merged groups. Explicit metadata normalization may continue in bounded pages and must preserve the existing pending-edit safety path.
7. The implementation shall not load the full track library into memory. SQL grouping and existing 200-track normalization pages remain bounded.
8. Existing uncommitted work and the protected-database Gemini key design shall remain intact.

## Acceptance examples

- `jazz`, `JAZZ`, `ジャズ` -> `Jazz`
- `Smooth-Jazz`, `Smooth Jazz`, `スムース・ジャズ`, `スムースジャズ` -> `Smooth Jazz`
- `J POP`, `J-POP`, `j-pop` -> `J-Pop`
- `ソウル／R&B`, `Soul / R&B`, `soul-r&b` -> `Soul / R&B`
- `ヴィジュアル系ロック` -> `Visual Kei Rock`
