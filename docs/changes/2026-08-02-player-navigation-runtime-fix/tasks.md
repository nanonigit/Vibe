# Player Navigation Runtime Fix Tasks

- [x] Add regression tests for player-specific album and artist routing.
- [x] Add explicit player navigation methods to `LibraryViewModel`.
- [x] Connect both shared-player click targets to those methods.
- [x] Build and run focused/full tests. (The generated macOS test bundle passed all 173 tests when run directly with `xctest`.)
- [x] Build the Apple Silicon app and verify the launched process. (Release 0.16 was installed at `/Applications/Vibe.app` and launched as PID 8530.)
- [x] Record investigation, RCA, fix, and prevention in English and Japanese.
