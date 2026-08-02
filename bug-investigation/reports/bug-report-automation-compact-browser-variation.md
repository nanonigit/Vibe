# Bug Report: Automation, Compact Layout, Browser Translation, and Variation Repair

## Symptoms

- Checked metadata automations still exposed separate start/stop controls, so the checkbox did not clearly own the task lifecycle.
- The library toolbar and player clipped or overlapped when their pane became narrow.
- Browser translation could not be disabled persistently or toggled from the visible browser status.
- Metadata variation candidates could be inspected, but neither spelling could be selected as the canonical value.

## Reproduction Evidence

1. Enable a metadata automation and observe the additional manual start/stop button.
2. Narrow the center or inspector pane and observe controls competing for one horizontal row.
3. Open an external article and observe that translation behavior has no persistent on/off control.
4. Open a variation pair and observe that the only available action is exclusion.

## Expected

- The checkbox is the single start/stop control and progress remains passive.
- Controls reflow before they overlap, with all player actions preserved.
- Translation is persistent, immediately affects the current page, and is toggled from settings or the browser status.
- Either candidate value can be chosen after confirmation and is written through the existing safe metadata path.
