# Hybrid Genre Pipeline Design

## Evidence

MusicBrainz officially exposes entity genres through `inc=genres`. Its public service currently limits a source IP to an average of one request per second and requires a meaningful User-Agent. Vibe reuses its existing throttled MusicBrainz service.

## Flow

1. Query the local database for the dominant non-empty genre among matching album/artist tracks.
2. Run `LocalGenreClassifier`; accept only confidence >= 0.80.
3. Search an exact release group on MusicBrainz and look it up with `inc=genres`; choose the most-voted genre. Cache success and no-match results by normalized album/artist.
4. Fall back to OpenAI, then Gemini.
5. Store only in Vibe's library database, update live facets, and expose per-source counters.

## Safety

- Sequential MusicBrainz requests use the existing 1.1-second throttle.
- Exact normalized album and artist matching prevents unrelated search hits.
- No-match cache avoids repeated network calls for every track on the same album.
- Cancellation is checked between every stage.
