# Hybrid Genre Pipeline Requirements

- Automatic genre registration must not send every unclassified track directly to external AI.
- Resolve genres in this order: trusted library consensus, high-confidence local rules, MusicBrainz genres, then configured external AI.
- Preserve existing genres and register only results with at least 80% confidence.
- Cache MusicBrainz results per album/artist during a scan and respect its request-rate policy.
- Missing MusicBrainz data is not an error; only a failure of every applicable source counts as failed.
- Do not upload audio. Keep Gemini credentials in the protected app database.
- Progress must identify the current source and show registration counts by source.
