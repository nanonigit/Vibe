# Fix Log: Stable Library Search

## Repair

- Moved the single search field outside the `ViewThatFits` candidates.
- Added a `FocusState` owned by `ContentView` and passed its binding to the field.
- Set the search field to a stable 360-point width from the first frame.
- Replaced conditional progress text with a permanently allocated 16-point spinner slot whose opacity changes.
- Added source-level regression assertions for focus ownership, one search instance, fixed width, and stable progress geometry.

## Preserved behavior

- 280 ms debounce, section navigation, database search, clear action, and accessibility label remain available.

## Verification

- Full macOS test suite: 163 tests passed.
- Release build: succeeded for Apple Silicon (`arm64`).
- The ad-hoc-signed Release app was installed at `/Applications/Vibe.app`, launched successfully, and visually confirmed to show the full-width search field before input.
