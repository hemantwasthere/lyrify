/**
 * A staged still of the overlay. Four lines share one 8s cycle on staggered
 * negative delays, so the highlight is already mid-run when the page loads and
 * walks down the verse the way the real overlay does.
 */
const LYRICS = [
  "the city hums a quiet song",
  "a light stays on till you get home",
  "and every word you thought you'd lost",
  "comes back around, right on time",
];

export function PlayerMock() {
  return (
    <div>
      <div className="rounded-2xl border border-border bg-surface p-[22px] shadow-card">
        <div className="flex items-center gap-[14px]">
          <div
            aria-hidden="true"
            className="vinyl-sm size-[46px] shrink-0 animate-disc rounded-full border border-border"
          />
          <div className="min-w-0">
            <div className="text-[0.95rem] font-semibold">Sample Track</div>
            <div className="font-mono text-[0.76rem] text-text-dim">
              Demo Artist
            </div>
          </div>
        </div>

        <div
          aria-hidden="true"
          className="mt-5 flex flex-col gap-[10px] border-t border-border pt-[18px]"
        >
          {LYRICS.map((line, i) => (
            <div
              key={line}
              className="animate-lyric font-display text-[1.02rem] text-text-dim opacity-50"
              style={{ animationDelay: `${i * -2}s` }}
            >
              {line}
            </div>
          ))}
        </div>
      </div>

      <p className="mt-4 font-mono text-[0.68rem] uppercase tracking-[0.08em] text-text-dim opacity-70">
        Simulated — actual sync tracks real playback
      </p>
    </div>
  );
}
