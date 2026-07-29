# AI Genre Scan Fix Log

- Replaced 500-row bundled classification with sequential OpenAI/Gemini requests.
- Kept provider keys in the protected application database and avoided logging secret values.
- Published progress after each track.
- Added separate registered, below-80%, and failed counters.
- Added a three-consecutive-provider-failure cooldown: it counts down for 10 seconds, remains cancellable, then resumes automatically.
- Added live genre-facet count updates after each successful registration.
- Added compact sidebar progress with the current track.
- Renamed MusicBrainz progress to “Analyzing album track order”.
- Added source-level regression coverage; 160 arm64 tests passed.
