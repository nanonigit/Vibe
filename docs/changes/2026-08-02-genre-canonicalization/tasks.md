# Genre Canonicalization Tasks

- [x] Inspect both checkouts, recent commits, and uncommitted changes.
- [x] Record requirements and design in English and Japanese.
- [x] Add failing canonicalization and grouped-query tests.
- [x] Harden `GenreNormalizer` aliases and non-destructive fallback.
- [x] Merge canonical genres at database query boundaries without scanning every track in Swift.
- [x] Canonicalize import and direct-update paths.
- [x] Run the genre tests, full suite, and arm64 Debug build (genre tests pass; four pre-existing unrelated tests remain red).
- [x] Review the final diff without staging unrelated files.
