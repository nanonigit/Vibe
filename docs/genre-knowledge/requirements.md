# Genre Canonicalization and Knowledge Requirements

## Context

Vibe currently normalizes known aliases with a bundled dictionary. The maintenance job is functioning, but unknown Japanese labels are intentionally preserved to avoid misleading partial translations. This leaves duplicate facets across language and casing, and the settings status does not distinguish enabled, running, and completed states.

## Functional requirements

- R1: Every newly suggested or automatically registered genre name shall be stored as a concise English canonical label.
- R2: The system shall merge case, punctuation, separator, and Japanese/English aliases into the same canonical genre.
- R3: Known aliases shall continue to resolve offline through `GenreNormalizer`.
- R4: An unknown Japanese genre shall be resolved through a bounded web lookup, cached by its raw label, and reused without another request.
- R5: A web result shall only be applied when an English Wikipedia language link and a music-related result are available; otherwise the original value shall remain visible and be reported as unresolved.
- R6: Existing track updates shall retain the 200-track paging, pending-edit queue, ID3 repair safeguards, and cancellation behavior.
- R7: Genre knowledge shall persist the canonical English name, Japanese and English summaries when available, source title, source URL, and resolution timestamp.
- R8: Genre rows shall remain compact and show one short description beside the English canonical name.
- R9: A selected genre shall show a longer description and a clickable source attribution.
- R10: The management screen shall distinguish disabled, enabled/idle, running progress, completed result, and unresolved counts.
- R11: No full-library scan or production database mutation shall be performed during development or verification without explicit user confirmation.

## Non-functional requirements

- Network work shall be sequential or tightly bounded and shall never scale with all 370,000 tracks when one lookup per unique raw genre is sufficient.
- Wikipedia requests shall use an identifying User-Agent, timeouts, and HTTPS.
- Source text shall be summarized or displayed from the API extract with attribution; Vibe shall not present generated text as verified fact without a source.
- Failures shall be non-destructive: keep the original genre, persist no false canonical mapping, and surface an unresolved count.
- Existing offline behavior shall remain available for bundled aliases and cached knowledge.

## Acceptance criteria

- `jazz`, `JAZZ`, and `ジャズ` group as `Jazz`.
- Unknown Japanese values no longer silently appear completed: they become resolved English labels or are counted as unresolved.
- AI providers are prompted to return the genre label in English even when the UI language is Japanese.
- Cached knowledge supplies list/detail descriptions and a source URL after relaunch.
- The settings status reports the most recent checked, updated, and unresolved totals.
