# Fix Log

- Automation preference save handlers now start work when enabled and cancel it when disabled.
- Redundant start/stop buttons were replaced by passive status labels.
- The library header uses a compact stacked toolbar and a flexible full-row search field when horizontal space is constrained.
- The shared player selects a narrow layout while retaining artwork, identity, shuffle, repeat, mini-player, volume, transport, and seek controls.
- External-article translation is persisted, exposed in Display settings, and bound to a clickable browser status. Changing it reloads the current original/translated page immediately.
- Each metadata variation value now offers a confirmed canonicalization action that gathers exact matches and routes them through the existing safe batch metadata writer.
- Regression checks cover each repaired behavior.
