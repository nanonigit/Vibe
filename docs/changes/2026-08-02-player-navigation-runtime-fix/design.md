# Player Navigation Runtime Fix Design

## Evidence

Lazyweb research on desktop music players supports treating artwork, track identity, and artist identity as direct, uncluttered navigation targets. Vibe already exposes those visual targets, so the repair keeps the layout and strengthens destination semantics rather than adding controls.

## Design

- Keep the existing plain buttons and their full label hit areas.
- Route artwork/title through a player-specific album method.
- Resolve the album artist as trimmed `albumArtist`, falling back to trimmed `artist`.
- Capture the current browse state before switching sections.
- Enter `.albums` or `.artists` explicitly, clear incompatible detail filters, and then load the destination.
- Keep generic table/header navigation unchanged to avoid regressions in existing Back-stack behavior.
