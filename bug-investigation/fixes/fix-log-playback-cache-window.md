# Fix Log: Player Controls, Cache Status, and Window Restoration

## Timeline

1. Reproduced missing behavior with regression tests.
2. Added cached byte aggregation and bounded random selectors.
3. Added whole-library shuffle with live root detection and validated-cache fallback.
4. Hid both menu indicators and kept shuffle/repeat adjacent.
5. Added normal-window frame persistence with visible-screen fitting.
6. Ran 158 tests successfully.

## 5 Whys

1. Why was the repeat icon malformed? The native menu indicator remained visible.
2. Why was it visible? The menu was styled but its indicator was never disabled.
3. Why was whole-library shuffle missing? Playback state represented only on/off shuffle within an existing sequence.
4. Why was cache size missing? The aggregate returned cache rows but not their recorded byte sum.
5. Why was the window not restored? Mini-player restoration captured only the current process frame and had no cross-launch persistence.

## Fishbone summary

- UI framework: default menu indicator.
- State model: no global shuffle scope.
- Data query: cached bytes omitted from aggregate.
- Lifecycle: window frame stored only in transient SwiftUI state.
- Scale: a full-library array would be unsafe, requiring indexed bounded selection.
