# RCA: Split Genre Taxonomy

## 5 Whys

1. Why are duplicates visible? Raw genre strings are grouped.
2. Why are raw strings grouped? Canonicalization was added only to edit paths.
3. Why did case-only handling not solve it? `COLLATE NOCASE` does not translate or fold punctuation.
4. Why can unknown labels be damaged? The fallback deletes unmatched Japanese characters.
5. Why was this missed? There were no focused normalizer and end-to-end facet tests.

## Fishbone

- Data: multilingual historical tags.
- Logic: partial exact map plus destructive fallback.
- Database: inconsistent raw/NOCASE grouping.
- Process: no canonical-query acceptance test.

## Timeline

- Aug 1: normalizer and background rewrite introduced.
- Aug 2: screenshot exposed 1,000+ split labels and Japanese output.
- Aug 2: active checkout and dirty worktree inspected before corrective work.

## Root cause

Canonical genre identity was not defined and enforced at the read/query boundary.
