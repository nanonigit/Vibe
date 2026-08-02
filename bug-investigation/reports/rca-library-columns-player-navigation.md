# Root Cause Analysis: Library Columns and Player Navigation

## Timeline

1. Library tables grew around title, artist, album, and counts.
2. Release-year metadata and genres became available through later metadata automation.
3. The table contracts and player identity remained unchanged.
4. The missing context became visible once automation populated more metadata.

## 5 Whys

1. Why was the context missing? The views had no corresponding columns or actions.
2. Why were there no columns? Sort and summary models did not expose the fields.
3. Why did models not expose them? The original table contract predated metadata automation.
4. Why was player navigation absent? Identity labels were passive text inside the shared control.
5. Why did this persist? No regression test expressed metadata-to-navigation expectations.

## Fishbone

- **Model:** no year sort or artist genre field.
- **Data:** no deterministic representative-genre aggregation.
- **View:** no visibility, width, header, or cell wiring.
- **Interaction:** player identity used passive labels.
- **Tests:** no end-to-end source contract for the requested behavior.

## Root Cause

Metadata production expanded without a matching read-side presentation and navigation contract.
