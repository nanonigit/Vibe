# Fix Log: Genre Canonicalization

## Change

- Expanded Japanese-to-English aliases for the labels visible in the reported Genre screen.
- Added punctuation- and case-insensitive keys for middle dots, slashes, hyphens, spaces, and full-width forms.
- Preserved unmapped Japanese labels instead of silently deleting their text.
- Merged raw genre facets and counts under one canonical English label.
- Resolved a selected canonical genre to its raw aliases before querying tracks, albums, artists, and storage totals.
- Canonicalized genre values on imports and direct database updates.
- Repaired the pre-existing synthetic-track fixture after the `year` column had been added.

## Safety

No real library scan or audio-file metadata rewrite was run. Verification uses temporary test databases and an arm64 build.
