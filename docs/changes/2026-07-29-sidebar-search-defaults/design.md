# Sidebar Defaults and Stable Search Design

## Sidebar initialization

`LibraryViewModel` defines one explicit default order and one explicit default hidden set. The initializer applies these defaults only when the corresponding database setting is absent. An empty stored string remains a valid user choice, so “Show All” is not mistaken for an uninitialized preference.

## Search identity and layout

`ContentView` owns the search `FocusState`, because it remains alive when the selected library section changes. `LibrarySearchField` receives that binding. The field uses a fixed width from its first frame. A fixed-size progress slot remains in the hierarchy and changes opacity instead of being inserted and removed, preventing `ViewThatFits` from selecting a different layout branch while typing.

The clear button may appear within the fixed-width container without changing the container size. Search execution and debounce behavior remain unchanged.

## Root-cause summary

The previous flexible intrinsic width grew when the “Searching…” label appeared. That could switch the parent `ViewThatFits` candidate and recreate the search subtree. AppKit then resigned the text field as first responder. Stable geometry and parent-owned focus remove both triggers.
