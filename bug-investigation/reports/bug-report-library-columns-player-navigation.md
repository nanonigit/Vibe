# Bug Report: Missing Library Context and Player Navigation

## Summary

- **Observed:** Track and album tables did not expose release year, artist rows did not expose genre, and player metadata was not navigable.
- **Expected:** Optional persistent columns should expose this context, and player metadata should open its album or artist.
- **Impact:** Users had to open detail views or search manually to answer basic library questions.

## Reproduction

1. Open Songs, Albums, or Artists.
2. Open the column visibility menu.
3. Observe that Release Year or Genre is absent.
4. Play a song and click its artwork, title, or artist.
5. Observe that no library navigation occurs.

## Evidence

Source inspection confirmed the enum, database summary, table, and shared player lacked these paths. Regression tests now cover paging, sorting, persistent column wiring, and shared-player actions.
