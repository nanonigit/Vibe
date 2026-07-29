# Sidebar Defaults and Stable Search Requirements

## Requirements

- When no sidebar customization has been saved, the Library section must initially show, in order: Cache, Artists, Albums, Songs, Genres, Favorites.
- Up Next, Recently Added, and Folders must be hidden only in that initial unsaved state.
- A saved order or visibility choice, including an explicitly saved empty hidden set, must remain authoritative.
- The library search field must keep keyboard focus while incremental search updates the displayed section and results.
- The search field must use its full intended width before the user types and must not resize when search progress appears.
- Search progress and clear controls must not structurally replace the focused text field.

## Acceptance Criteria

- Default order and hidden-section constants are covered by regression tests.
- Stored sidebar customization is decoded exactly as before.
- Search focus is owned by the stable parent view and passed into the search component.
- The search component has one fixed width and reserves a fixed progress-control slot.
