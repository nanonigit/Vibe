# Vibe 0.16.0 Release Requirements

- Update the English and Japanese READMEs to match the current application behavior.
- Keep reciprocal language links and document both Homebrew and direct-download installation.
- Describe only features present in the tested source tree, including hybrid genre resolution, six appearance themes, stable search, BPM/practice tools, cache status, and window restoration.
- Set the application version to 0.16 and build number to 16.
- Produce an Apple Silicon Release archive named `Vibe-v0.16.0-macos-arm64.zip`.
- Verify tests, Release build, arm64 architecture, signature, archive contents, and checksum before publishing.
- Commit and push the application source before creating the GitHub release.
- Publish GitHub release `v0.16.0` with accurate bilingual release notes and the verified archive.
- Update the `nanonigit/homebrew-vibe` Cask to 0.16.0 with the exact published archive checksum, validate it, commit it, and push it.
- Do not commit API keys, local databases, audio paths, build outputs, or project-local agent tooling.
