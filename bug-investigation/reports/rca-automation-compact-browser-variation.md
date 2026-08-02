# Root Cause Analysis

## Five Whys

1. Why were the controls confusing or clipped? State and layout ownership were split across independent controls and fixed horizontal stacks.
2. Why was ownership split? Features were added incrementally without one source of truth for lifecycle, width class, or browser translation state.
3. Why did width changes fail? The views relied on fixed widths instead of selecting a layout that fits the available pane.
4. Why could translation and variations not update in place? They were display-only flows with no shared binding or canonicalization command.
5. Why was this not caught? Regression checks covered feature presence more than lifecycle ownership and narrow-pane behavior.

## Fishbone

- **State:** checkbox values and running tasks could diverge.
- **Layout:** fixed-width toolbars and player rows assumed a wide pane.
- **Browser:** translation policy lived inside navigation handling instead of a persisted binding.
- **Metadata:** variation analysis had navigation/exclusion but no safe write action.
- **Tests:** no explicit assertions for single-control lifecycle, narrow variants, current-page translation reload, or either-value selection.

## Timeline

1. Independent automation buttons and fixed layouts were introduced as features grew.
2. External translation and variation analysis were added as one-way display flows.
3. Narrow panes and real repair workflows exposed the missing ownership and reflow rules.
4. Tests were added first, then the shared state and adaptive layouts were repaired.
