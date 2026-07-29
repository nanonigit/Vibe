# Lessons Learned: Focused Controls in Adaptive Layouts

- Do not duplicate focused controls across `ViewThatFits` candidates.
- Keep asynchronous status indicators in fixed geometry when they share a row with text input.
- Own focus at a view level that survives navigation-state changes.
- Add regression checks for both stable view identity and stable dimensions, not only for search results.
