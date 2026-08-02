# Player Navigation Prevention

1. Verify that the installed app timestamp is newer than the source change before accepting UI runtime results.
2. Player-originated navigation must set its destination section explicitly and clear incompatible transient filters.
3. Album navigation must use the same normalized artist key as database grouping.
4. Keep a regression test for both click wiring and metadata-key resolution.
5. Do not claim runtime verification until the newly built app is launched and the click path is observed.
