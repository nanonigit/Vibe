# Vibe 0.16.0 Release Design

## Documentation

`README.md` remains the English source and `README.ja.md` its Japanese counterpart. The feature list is organized around library scale, offline storage, playback/practice, discovery, metadata safety, genre automation, and appearance. Installation presents Homebrew first and a versioned GitHub archive second.

## Versioning and artifact

The application Info.plist source and XcodeGen specification use version 0.16/build 16. The Release build targets `platform=macOS,arch=arm64`. The signed `Vibe.app` is zipped with `ditto`, inspected after extraction, and hashed with SHA-256.

## Publication order

1. Verify source and documentation.
2. Commit and push `main`.
3. Create tag/release `v0.16.0` and upload the archive.
4. Confirm the remote asset checksum.
5. Update and validate the Homebrew Cask against that checksum.
6. Commit and push the tap, then run Homebrew audit/style checks when available.

## Safety boundaries

Build products stay outside Git. `.agents/` and `skills-lock.json` are excluded because they are local agent tooling rather than Vibe product sources. Gemini credentials continue to use the protected in-app database.
