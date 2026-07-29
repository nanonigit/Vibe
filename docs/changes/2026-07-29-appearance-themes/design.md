# Appearance Theme Design

## Research basis

Lazyweb desktop theme examples favor Todoist-style color preview cards and Slack/Craft-style light/dark grouping over a text-only picker. Vibe presents six cards in Dark and Light groups.

## Structure

- Expand `AppearanceMode` to six themes, each exposing an `AppearancePalette`.
- The palette defines canvas, sidebar, library, inspector, elevated, divider, selection, and accent colors.
- Apply scheme/accent at the root and explicit surfaces to each primary pane.
- Synchronize the SwiftUI color-scheme environment and the owning `NSApplication`/`NSWindow` appearance so AppKit-backed controls do not retain dark semantic colors in light themes.
- Use compact three-pane preview cards in a two-column grid, with a border and checkmark for selection.
- Persist raw values in `app.appearance`; map legacy values during initialization.
