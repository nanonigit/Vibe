# Fix Log: Light Theme Contrast

- Symptom: Light surfaces appeared, but labels and AppKit-backed controls retained dark-theme colors, making text unreadable.
- Root cause (5 Whys): The palette changed SwiftUI surfaces while native window appearance stayed dark, so semantic colors resolved against the wrong appearance.
- Fix: A synchronizer hosted inside the model-observing player views updates `NSApplication.appearance` and every Vibe window whenever the persisted theme changes. It avoids a stale parent-level color-scheme override, so light-to-dark and dark-to-light both work.
- Verification: Check all three light themes, native text fields and table headers, arm64 Release build, and live restart.
- Prevention: Every future theme must verify both SwiftUI surfaces and AppKit-backed semantic controls.
