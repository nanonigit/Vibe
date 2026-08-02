# Prevention Notes

- A persistent checkbox that represents a background feature must be the only normal start/stop control for that feature.
- Every pane-owned toolbar and player must define a narrow layout that preserves actions and reflows before overlap.
- Browser transformation policy must be injected as shared state, preserve the original URL, and support immediate reevaluation.
- Diagnostic repair actions must use exact filters, explicit confirmation, and the same writer/backup path as normal edits.
- Keep static wiring checks for UI ownership and add runtime/database coverage wherever the behavior can be isolated safely.
