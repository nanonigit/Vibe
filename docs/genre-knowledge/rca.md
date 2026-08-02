# Root Cause Analysis: Japanese Genres Remain After Automatic Standardization

## Symptom and impact

The genre browser still shows Japanese labels while the management toggle says automatic standardization is on. Users cannot tell whether the job is broken, incomplete, or intentionally preserving a value.

## Timeline

- 2026-08-01: static `GenreNormalizer` and background merge job added.
- 2026-08-02 17:23: Japanese genre facets observed in the running v0.16 app.
- 2026-08-02 17:28: management UI confirmed the toggle is on; the separate missing-genre AI scan was actively processing.
- Investigation: all sampled remaining Japanese labels were absent from the static map; the normalizer safety guard returned them unchanged.

## 5 Whys

1. Why do Japanese genres remain? Their raw labels are not in the alias dictionary.
2. Why are unknown labels not translated? Partial replacement could produce a misleading hybrid label, so the safety guard returns the original.
3. Why can the dictionary not cover the library? AI-generated and imported labels form an open-ended vocabulary.
4. Why does the UI look as if processing stopped? Completion clears progress and falls back to “automatic standardization is on.”
5. Why was this not obvious? No unresolved total, retained completion result, or source-backed knowledge record exists.

## Fishbone

- Data: open-ended Japanese aliases and casing variants.
- Algorithm: static exact/partial map only; safe fallback preserves unknowns.
- State: cursor persists, but completion/unresolved summaries do not.
- UI: enabled and completed/idle are collapsed into one message.
- Verification: tests cover known aliases and preservation of unknown Japanese, but not an online resolution path.

## Corrective and preventive actions

- Add a small persistent genre knowledge table keyed by raw alias.
- Resolve unknown Japanese labels through a validated, attributed web source.
- Keep unresolved values unchanged and count them explicitly.
- Force all new AI genre labels to English.
- Retain the last completion totals and surface source attribution in the genre UI.
- Add regression tests for persistence, language policy, and status semantics.

## Verification

- The first regression run failed before the knowledge model and persistence APIs existed.
- The final suite passed all 176 tests with no failures or skips.
- Debug and arm64 Release builds passed; the separate v0.17 artifact passed deep strict ad-hoc signature verification.
- The production database, audio files, installed app, and running normalization cursor were not modified.
