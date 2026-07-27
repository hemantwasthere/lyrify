/**
 * The app's mark: a record with a played arc struck through the groove ring and
 * a stylus dot at its head. Colours are fixed rather than themed — it is the
 * same mark as the icon on the user's disk.
 */
export function LyrifyMark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 512 512" aria-hidden="true" className={className}>
      <defs>
        <radialGradient id="lyrify-disc-body" cx="38%" cy="32%" r="75%">
          <stop offset="0%" stopColor="#24392f" />
          <stop offset="100%" stopColor="#0f1815" />
        </radialGradient>
      </defs>
      <circle cx="256" cy="256" r="248" fill="url(#lyrify-disc-body)" />
      <circle
        cx="256"
        cy="256"
        r="248"
        fill="none"
        stroke="#3a5346"
        strokeWidth="3"
      />
      <circle
        cx="256"
        cy="256"
        r="176"
        fill="none"
        stroke="#4a6357"
        strokeWidth="9"
        opacity="0.55"
      />
      <circle
        cx="256"
        cy="256"
        r="176"
        fill="none"
        stroke="#e6a339"
        strokeWidth="11"
        strokeDasharray="220 886"
        strokeLinecap="round"
        transform="rotate(-90 256 256)"
      />
      <circle cx="423" cy="200" r="10" fill="#e6a339" />
      <circle cx="256" cy="256" r="34" fill="#e6a339" />
      <circle cx="256" cy="256" r="10" fill="#0f1815" />
    </svg>
  );
}
