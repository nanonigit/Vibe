# Design: Checkbox Automation and Compact Layout

## Evidence

Lazyweb desktop references for Todoist, Sunsama, Linear, and Microsoft Loop consistently use a toggle as the sole enable/disable control for a persistent automated preference and keep state/progress explanatory rather than presenting a second action button. Lazyweb table references such as Amplitude separate search from denser table controls when horizontal room is constrained. We apply those patterns without changing Vibe's visual language.

## Automation state model

The persisted Boolean is the single source of truth:

1. `false -> true`: persist `true`, start the matching job if it is not running.
2. `true -> false`: persist `false`, cancel the matching task and clear transient running state.
3. App launch: load the Boolean and start only enabled jobs.
4. Job completion: leave the Boolean enabled so future imports or launches can run the automation again.

Progress rows contain only text. Explicit MusicBrainz retry buttons remain because they recover completed exceptional results rather than duplicating the enable/disable state.

## Responsive library header

Use `ViewThatFits(in: .horizontal)` with two variants:

- Regular: identity, control cluster, and fixed-width search field on one row.
- Compact: identity on the first row, control cluster on the second row, and a flexible search field on the third/second control row as space permits.

The compact search field uses a flexible width rather than the fixed 360-point frame.

## Responsive player

Use one shared control component with two internal arrangements selected by `ViewThatFits`:

- Regular (minimum 420 points): artwork beside a content column whose first row combines title and utility controls.
- Narrow: artwork and identity at the top, utility controls below the identity, then transport and seek rows across the full player width.

No control is removed in the narrow version.

## Translation state and current-page reload

The persisted Boolean is passed into the embedded browser as a binding. The toolbar status is a plain full-label button, so the icon and text share one hit target. The WebKit coordinator records the original article URL before creating a translation URL. When the Boolean changes, it reloads that original URL directly when disabled, or its translated URL when enabled. Navigation policy bypasses all translation routing while disabled.

## Variation choice and safe write path

Each candidate row keeps its existing links for inspection and adds `Use This Spelling` beside both values. Selection creates a confirmation request containing the candidate and chosen value. After confirmation, only tracks whose exact field equals the other value are loaded and handed to the existing batch metadata update path. This preserves file verification, ID3 repair policy, offline pending edits, progress, and activity logging. Candidate refresh already removes rows whose source count reaches zero.

## Root-cause summary

The current screen exposes both a persisted checkbox and separate start/stop buttons. The AI genre stop button cancels only the task, not the persisted checkbox, so the next launch starts it again. Fixed widths in the header and a wide first player row then exceed the proposed pane width and are clipped.
