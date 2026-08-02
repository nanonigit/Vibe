# Player Navigation Runtime Fix Requirements

## Goal

Make the now-playing controls a reliable entry point into the local library hierarchy.

## Requirements

1. Clicking the player artwork or track title must open the current track's album detail.
2. Clicking the displayed artist name must open that artist's detail.
3. Album navigation must use `albumArtist` when present so compilation and album grouping match the database.
4. Player navigation must explicitly enter the Albums or Artists library section while preserving the previous browse state for Back navigation.
5. Empty album or artist metadata must remain non-interactive instead of opening an invalid detail.
6. The behavior must be shared by the inspector player and mini player.
