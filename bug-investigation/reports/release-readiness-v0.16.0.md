# Release Readiness Analysis: Vibe 0.16.0

## Scope

Publish the accumulated tested Vibe changes as an Apple Silicon GitHub release and update the official Homebrew Cask without exposing local data or producing mismatched version/checksum metadata.

## Timeline

1. Inspected the dirty worktree, remote `main`, current `v0.15.0` release, and `homebrew-vibe` Cask.
2. Defined release requirements and publication order before changing release metadata.
3. Updated bilingual documentation and version metadata.
4. Run the complete tests, arm64 Release build, signing, archive, and checksum gates.
5. Review and push the exact product changes.
6. Publish and independently verify the GitHub asset.
7. Update and validate the Homebrew Cask using the published checksum.

## 5 Whys: preventing a broken Homebrew release

1. Why could Homebrew installation fail? The Cask could contain a version or checksum that does not match the release asset.
2. Why could they differ? The Cask might be edited before the final archive is created or uploaded.
3. Why would that happen? Release, checksum, and tap updates might be treated as independent tasks.
4. Why is that unsafe? GitHub can accept a replaced or differently packaged asset while the Cask remains pinned to an earlier digest.
5. Why does the process prevent it? The tap is updated only after downloading the published asset and comparing its SHA-256 with the locally verified archive.

## Fishbone analysis

- **Source:** unrelated `.agents/` tooling could be staged; mitigate with an explicit path-based stage list.
- **Build:** an old DerivedData lock or stale app could be packaged; mitigate with a fresh release directory and bundle-version inspection.
- **Architecture:** a universal or Intel binary could be distributed accidentally; mitigate with `file` and `lipo -archs`.
- **Signing:** an invalid nested-framework signature could launch locally but fail after packaging; mitigate with deep strict verification before and after extraction.
- **Documentation:** README claims could drift from the app; mitigate by tracing feature claims to source/tests and using reciprocal English/Japanese updates.
- **Distribution:** the Homebrew checksum could drift; mitigate by hashing the remote asset before the Cask commit.

## Release gates

- Full test suite passes.
- `git diff --check` passes and no credential patterns are present in staged content.
- App reports version 0.16/build 16 and executable architecture arm64.
- Deep strict code-signature verification passes before and after ZIP extraction.
- GitHub asset name, size, and SHA-256 are verified after upload.
- Homebrew Cask references the same version, URL pattern, and SHA-256.

## Verification result

- 163 tests in 3 suites passed.
- Release build succeeded; the packaged app is version 0.16/build 16 and arm64.
- The local and independently downloaded GitHub archives both have SHA-256 `b8d3bf41fb8accc43f8693b6536260ec73845a48dd26e012cdc27841e4f614ab`.
- Deep strict signature verification passed after extracting both the local and remote archives.
- GitHub release `v0.16.0` targets commit `fda74089a0b7a94c2b39d97e9495c494ec7387a0`.
- Homebrew Cask commit `9c92b00945e3eeaa49db89a5bf11d123256b139e` passed `brew style` and `brew fetch` checksum verification.
- `brew audit --online --strict` could not start because the installed Homebrew currently requires Xcode 27.0 while this Mac has Xcode 26.6; this is an environment prerequisite failure, not a Cask finding.
