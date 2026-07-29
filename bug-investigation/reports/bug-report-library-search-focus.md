# Bug Report: Library Search Loses Focus and Resizes

- Date: 2026-07-29
- Severity: Major usability issue
- Scope: Library header search on macOS

## Reproduction

1. Open a library section such as Albums or Artists.
2. Click the header search field.
3. Type a short query.
4. Wait for the 280 ms incremental-search debounce.

Expected: typing can continue and the field keeps the same size.

Actual: the field can lose focus, and its width grows when progress UI appears.

## Evidence

The search field was inside both candidates of a parent `ViewThatFits`. Its flexible width changed when a conditional progress label appeared. The debounce also changes the current section to Songs. Those state and geometry changes allowed SwiftUI to select another layout candidate and replace the focused text-field subtree.
