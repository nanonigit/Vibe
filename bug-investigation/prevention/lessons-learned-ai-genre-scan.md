# AI Genre Scan Prevention

- Tests for AI features must assert the actual provider call path, not only labels and thresholds.
- Batch size and user-visible progress granularity are separate concerns; publish per unit of meaningful work.
- Distinguish low-confidence results from operational failures.
- Long-running external-provider loops need a visible, cancellable cooldown instead of forcing manual restarts after transient outages.
- Background status labels must name the operation, such as album track-order analysis.
