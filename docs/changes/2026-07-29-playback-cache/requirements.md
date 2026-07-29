# Playback and Cache Status Requirements

## Functional requirements

- The repeat control shall render as a single, unambiguous icon without a second disclosure glyph.
- Shuffle and repeat controls shall remain adjacent in the full and mini players.
- The shuffle menu shall offer random playback across the entire connected library.
- When no configured music root is connected, whole-library shuffle shall select only locally playable cached tracks.
- Global shuffle shall query bounded candidates and shall not load the full library into memory.
- The cache header shall display both cached track count and total cached file size.
- The inspector detail area shall not repeat the current track title and artist already shown by its player.
- Cache size shall update after cache additions or removals through the existing sidebar-count refresh path.
- The app shall restore the last normal-player window size and screen position on the next launch.
- A mini-player frame shall never overwrite the stored normal-player frame.
- A restored frame shall be constrained to the currently visible screen area.

## Constraints

- Existing per-list shuffle and repeat behavior must remain available.
- Stale cache database entries must not be selected as playable tracks.
- Gemini credentials must remain in the protected application database.
