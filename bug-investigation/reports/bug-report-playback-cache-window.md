# Bug Report: Player Controls, Cache Status, and Window Restoration

## Symptoms and expected behavior

- The repeat menu displayed an extra disclosure glyph beside its repeat symbol.
- Shuffle had no explicit whole-library mode and could not intentionally fall back to cached tracks while the external library was disconnected.
- The cache screen showed track count but not storage usage.
- The normal window frame was not explicitly restored across launches.

Expected behavior is a clear adjacent shuffle/repeat control pair, bounded whole-library shuffle with cache fallback, visible cache bytes, and restoration of the last normal window frame.

## Reproduction evidence

The supplied screenshots showed the extra repeat glyph and a cache header containing only a count. Source inspection showed a borderless SwiftUI `Menu` without a hidden indicator, list-scoped shuffle only, a `COUNT(*)`-only cache aggregation, and no persisted normal-window frame key.

## Impact

The defects affected playback discoverability, offline playback intent, storage awareness, and continuity between launches. No credential or metadata storage paths were changed.
