# Requirements: Checkbox Automation and Compact Layout

## Metadata automation

- When an automation checkbox is enabled, its background job shall start or resume automatically.
- When an automation checkbox is disabled, its background job shall be cancelled and shall not restart on the next launch.
- The settings screen shall not present a second start/stop control for the same automation.
- Running, waiting, and completed progress shall remain visible as passive status text.
- Existing safety rules, resumable cursors, MusicBrainz retry actions, and protected-database API key storage shall remain unchanged.

## Narrow library layout

- The library header shall not overlap or clip its cache controls, column menu, or search field as the center pane narrows.
- At compact widths, the search field shall move to its own full-width row while the smaller controls remain above it.
- The search field shall remain usable and retain a practical minimum width.
- Track columns may continue to scroll horizontally, but their headers shall not intrude into the inspector.

## Narrow player layout

- The inspector player shall keep artwork, title, shuffle, repeat, mini-player, volume, transport, and seek controls visible at the minimum inspector width.
- The normal player and mini player shall share the same controls and automatically select a compact arrangement when necessary.
- Wide layouts shall retain the current single-row presentation.

## External article translation

- Display settings shall expose a persistent on/off switch for automatic translation in the internal browser.
- When off, the browser shall open and navigate original page URLs without routing links through the translation service.
- When on, external article links shall continue to use the selected app language.
- Changing the setting shall reload the currently displayed article as its original or translated form immediately.
- The translation status text in the right pane shall be clickable across its full label and shall toggle the same persisted setting.

## Variation standardization

- Every metadata variation pair shall offer an explicit action beside both the upper and lower spelling.
- Choosing either spelling shall show the affected field, source spelling, destination spelling, and track count before writing.
- Confirmed changes shall use the existing safe metadata writer and offline pending-edit path rather than database-only replacement.
- After completion, resolved candidates and counts shall refresh without resetting the diagnostics context unnecessarily.

## Safety and compatibility

- Do not read or move provider keys to Keychain; Gemini and OpenAI keys remain in the protected app database.
- Do not trigger a real-library scan while testing this change.
- Preserve all unrelated working-tree changes.
