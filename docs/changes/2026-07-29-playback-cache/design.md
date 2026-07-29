# Playback and Cache Status Design

## UI

The shared player control surface keeps shuffle and repeat adjacent. Both are borderless menus with their native menu indicator hidden. Shuffle contains two actions: toggle shuffle for the current playback scope, and start whole-library shuffle immediately.

The cache header uses the existing compact secondary line and renders `track count · formatted size`, followed by the cache path.

The inspector player remains the single source of visible current-track identity. The detail tabs begin immediately below it instead of repeating title and artist labels.

## Playback selection

Whole-library shuffle is a separate playback scope. On each forward transition it resolves configured security-scoped roots and checks their current filesystem availability. If at least one root is connected, the database selects one available track from those roots. Otherwise it selects one track joined to `local_cache` and validates that the cached file still exists.

Selection uses an indexed ID threshold plus wrap-around, avoiding `ORDER BY RANDOM()` and full-array materialization. The seed advances for each choice.

## Cache metrics

`librarySidebarCounts()` returns `SUM(local_cache.file_size)` together with the existing cached count. `LibraryViewModel` publishes the byte count, and `ContentView` formats it with `ByteCountFormatter`.

## Window restoration

The root window stores its normal-player `NSRect` in `UserDefaults` after moves and resizes. Entering mini-player mode first captures and stores the normal frame. Mini-player resize notifications are ignored. On launch the stored frame is validated, applied, and passed through the existing visible-screen fitting logic so a disconnected monitor cannot leave the window off-screen.

## Root-cause summary

- Repeat icon: SwiftUI `Menu` added its default disclosure indicator beside the SF Symbol.
- Missing global shuffle: shuffle was scoped only to the current list/candidate path.
- Missing cache size: the sidebar aggregation exposed count but discarded the already-recorded `file_size` values.
