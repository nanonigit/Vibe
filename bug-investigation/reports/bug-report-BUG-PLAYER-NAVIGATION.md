# BUG-PLAYER-NAVIGATION

## Summary

Clicking the now-playing artwork or artist identity did not visibly navigate to the matching local album or artist detail in the running app.

## Expected

- Artwork and track title open the current album.
- Artist name opens the current artist.
- Back returns to the prior browse context.

## Evidence

- The installed `/Applications/Vibe.app` was dated 2026-08-01 14:13:50, while the source working tree already contained the newer navigation change from 2026-08-02.
- The original player route did not explicitly switch sections or clear an active search/filter.
- The original album route used `track.artist`, while database album grouping prefers `albumArtist`.

## Scope

The shared `UnifiedPlayerControls` affects both the right inspector and mini player.
