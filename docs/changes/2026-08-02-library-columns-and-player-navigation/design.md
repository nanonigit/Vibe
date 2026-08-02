# Design: Library Columns and Player Navigation

## Evidence

Lazyweb desktop-library research recommended keeping year metadata as a compact, optional table column rather than expanding row height. The hosted report is: https://www.lazyweb.com/report/lazyweb/27217aa7-2fc2-4a41-b591-c40085fd439c/

## Data model

- Add `TrackSort.year` and use the existing indexed/paged track query surface.
- Extend `ArtistSummary` with `genre`, defaulting to an empty string for compatibility.
- Build artist summaries from a filtered CTE. Rank non-empty genres per artist by track count, then case-insensitive name, and join rank 1 to the summary page.

## UI

- Put Release Year after Album in the default track column order; use a compact 85-point persisted width.
- Put Genre between Artist and counts in the artist table; allow visibility, resizing, and sorting.
- Render artwork, title, and artist as plain semantic buttons. Artwork/title call a shared album-navigation helper; artist calls the existing artist navigation.
- Use help and accessibility labels so the click targets are discoverable without adding visual clutter.

## Navigation

The helper constructs the same `AlbumSummary` identity already used by album cells, then calls `openAlbum`, preserving the existing browse-return stack and preventing a second navigation implementation.
