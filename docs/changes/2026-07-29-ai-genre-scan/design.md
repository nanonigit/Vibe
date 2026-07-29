# External AI Genre Scan Design

The scan reads configured provider keys once from the protected database, then pages missing-genre rows from SQLite without materializing the library. Each track is sent sequentially to OpenAI, with Gemini as fallback. A completed request updates all counters on the main actor before the next track begins.

Suggestions below 80% are counted separately from request/write failures. Three consecutive tracks for which every configured provider fails trigger a visible 10-second cooldown; the scan then resumes automatically. Cancellation remains responsive during the countdown. The bundled classifier remains available for lightweight playback suggestions, but is not used by this explicit external-AI scan.

The genre screen shows a detailed progress summary. The sidebar footer reuses the compact background-status presentation and adds the current track plus checked/registered/below-threshold/failed counts.
