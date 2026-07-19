# LRCLIB as the sole lyrics source

Spotify's public Web API exposes no lyrics at all — the lyrics shown inside the Spotify client are licensed from Musixmatch and served over a private endpoint. We therefore need an independent source of Synced Lyrics, and we have chosen **LRCLIB** as the only one for v1, reached through a provider abstraction so a second source can be added later without disturbing the rest of the app.

## Considered Options

- **LRCLIB** — purpose-built to serve time-synced lyrics to third-party players, no authentication, no legal cloud, returns both synced and plain forms. Weakness: community-contributed, so Coverage has gaps on obscure and very new releases.
- **Spotify's private lyrics endpoint** — would match Spotify's own Coverage almost exactly, but requires extracting an access token out of the client, violates Spotify's terms, breaks without warning on client updates, and produces an app that can never be distributed.
- **Musixmatch's unofficial API** — same fragility, worse legal position.
- **NetEase Cloud Music** — strong for CJK repertoire, weak for the Western catalogue.
- **Genius** — plain text only, so it cannot drive a synced overlay at all.

## Consequences

Coverage is now the product's principal quality limit, and it is one we largely cannot fix ourselves — when LRCLIB has nothing, Lyrify shows nothing. We accept that in exchange for an app that is legal, distributable, and not one Spotify release away from breaking.

Because LRCLIB is a free community service, Lyrify must identify itself honestly in its requests and cache aggressively, including caching misses, so that a popular client does not become a burden on it.
