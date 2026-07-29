/**
 * The app's mark: a record with a played arc struck through the groove ring and
 * a stylus dot at its head. Colours are fixed rather than themed — it is the
 * same mark as the icon on the user's disk, and must stay a redraw of
 * `Resources/Brand/logo-mark.svg` rather than a variation on it.
 *
 * The rim is a filled ring rather than a stroke, and a thick one. A pale disc
 * has no luminance contrast to spare against the cream page, so the edge
 * carries the silhouette the fill used to — at a stroke width that looked
 * right at full size it landed near half a pixel in the 16px favicon and
 * antialiased away to nothing.
 */
export function LyrifyMark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 512 512" aria-hidden="true" className={className}>
      <defs>
        <radialGradient id="lyrify-disc-body" cx="38%" cy="32%" r="75%">
          <stop offset="0%" stopColor="#f4ecdb" />
          <stop offset="100%" stopColor="#dbc9a6" />
        </radialGradient>
      </defs>
      <circle cx="256" cy="256" r="250" fill="#3d2f1a" />
      <circle cx="256" cy="256" r="220" fill="url(#lyrify-disc-body)" />

      <circle
        cx="256"
        cy="256"
        r="152"
        fill="none"
        stroke="#b09a70"
        strokeWidth="12"
        opacity="0.8"
      />
      <circle
        cx="256"
        cy="256"
        r="152"
        fill="none"
        stroke="#a86419"
        strokeWidth="18"
        strokeDasharray="190 766"
        strokeLinecap="round"
        transform="rotate(-90 256 256)"
      />
      <circle cx="400" cy="208" r="11" fill="#a86419" />

      <circle cx="256" cy="256" r="52" fill="#a86419" />
      <circle cx="256" cy="256" r="15" fill="#2b2216" />
    </svg>
  );
}
