# Root Cause Analysis: Player Navigation

## Timeline

1. Click handlers were added to the shared player source.
2. The source working tree was updated after the installed app's build date.
3. The older installed app continued running, so the visible behavior could not include the new handlers.
4. Source review also found destination ambiguity from inherited section/search state and album-artist mismatch.

## 5 Whys

1. Why did clicking appear to do nothing? The running binary did not reliably present the requested detail.
2. Why was the running binary missing the expected behavior? `/Applications/Vibe.app` predates the source change.
3. Why could a freshly built source route still fail for some tracks? It inherited the current section/search state.
4. Why could an album load as empty? The route used track artist instead of the database's album-artist grouping key.
5. Why was this not caught? The prior contract test checked only that click calls existed, not destination-state semantics or the deployed binary date.

## Fishbone

- Deployment: installed app older than source.
- Navigation state: section and search were inherited.
- Metadata: track artist and album artist may differ.
- Testing: source-string presence without destination behavior coverage.
- Environment: Xcode's normal test runner remained blocked by passcode-locked device discovery, so the successfully generated macOS test bundle was verified directly with `xctest` instead.

## Root Cause

The immediate observed failure is stale deployment. The code-level contributing causes are implicit destination context and an incorrect album grouping artist.
