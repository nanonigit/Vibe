# Bug Report: Split Genre Taxonomy

## Symptom

Equivalent genres appear as separate rows due to Japanese/English labels, case, and punctuation variants. The sidebar count and visible list can disagree.

## Reproduction

Import tracks tagged `Jazz`, `jazz`, `ジャズ`, `Smooth-Jazz`, and `スムース・ジャズ`; open Genres. Expected two canonical groups. Actual behavior depends on raw SQL grouping and may show multiple rows.

## Impact

Navigation, counts, AI registration feedback, and genre-detail results are unreliable in a large library.
