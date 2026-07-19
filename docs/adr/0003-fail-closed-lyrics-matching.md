# Uncertain lyrics matches fail closed

Matching a Track to a set of Synced Lyrics is attempted in three widening steps — an exact lookup on artist, title, album and duration; the same lookup with the album dropped; then a fuzzy search whose candidates are rejected unless their duration is within a few seconds of the Track's. If nothing survives, Lyrify declares that no lyrics were found rather than displaying its best guess.

Dropping the album on the second attempt is deliberate: Spotify frequently reports a single or a deluxe edition where the lyrics database holds the original album, and we expect this to be the most common cause of an otherwise perfectly good lookup failing.

## Consequences

Duration is the arbiter throughout, because the failure it guards against is specific and severe: lyrics from a live take, a radio edit or a remaster will drift steadily further out of time as the song plays. That reads to a user as a **broken app**, whereas an honest "no lyrics found" reads as a gap in the database. We would rather show nothing than something plausible and wrong.

The same logic extends to Plain Lyrics. When only untimed lyrics are available we show nothing at all, because a two-line overlay has no way to know which line is current, and a static line pinned on screen would actively mislead.

The cost is measurably lower Coverage than a looser matcher would achieve. That is the intended trade.
