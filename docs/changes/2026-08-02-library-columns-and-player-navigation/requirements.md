# Requirements: Library Columns and Player Navigation

## Release year

- Track tables shall offer a persistent Release Year column through the existing column menu.
- Release years shall sort using the existing paged database path and remain stable across pages.
- Missing years shall display as a quiet placeholder rather than an empty or misleading value.
- Album summary tables shall retain their existing Release Year column.

## Artist genre

- Artist list tables shall offer a persistent Genre column.
- The displayed value shall be the artist's most frequent non-empty library genre, with deterministic tie-breaking.
- Users shall be able to sort artist summaries by genre without loading all tracks into memory.
- Missing genres shall display as a quiet placeholder.

## Player navigation

- Clicking the current artwork or song title shall open that track's album.
- Clicking the current artist name shall open that artist page.
- Empty album or artist metadata and the not-playing state shall remain non-interactive.
- Inspector and mini-player controls shall share the same behavior.

## Safety

- Preserve paging, column-width persistence, browse return state, and protected-database API key storage.
- Do not scan or mutate the real music library during verification.
