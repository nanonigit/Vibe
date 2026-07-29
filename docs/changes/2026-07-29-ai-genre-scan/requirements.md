# External AI Genre Scan Requirements

- The automatic genre scan shall classify each unclassified track with a configured external provider, trying OpenAI before Gemini.
- The scan shall never present the bundled deterministic classifier as an external AI scan.
- Progress shall advance per completed track and show registered, below-threshold, and failed counts.
- The sidebar footer shall show the scan while it is running.
- Only suggestions with confidence of at least 80% shall be registered, and existing genres shall remain unchanged.
- API keys shall be read from the protected application database and shall never be logged.
- After three consecutive provider failures, the scan shall wait for 10 seconds and resume automatically instead of requiring another manual start.
- The retry countdown shall be visible in the genre screen and sidebar, and manual Stop shall remain available while waiting.
- Background MusicBrainz progress shall explicitly identify album track-order analysis.
