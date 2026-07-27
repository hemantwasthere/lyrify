import { Eyebrow, SectionHead } from "@/components/primitives";

const STEPS = [
  {
    label: "Install",
    body: "Download Lyrify and move it to Applications, like any Mac app.",
  },
  {
    label: "Open once",
    body: "It settles quietly into your menu bar — no dock icon, no clutter.",
  },
  {
    label: "Play something",
    body: "Hit play on any track in Spotify. The overlay appears on its own.",
  },
  {
    label: "Make it yours",
    body: "Drag it anywhere, resize it, or hide it with a click — it remembers.",
  },
];

export function HowItWorks() {
  return (
    <section className="py-[clamp(40px,7vw,72px)]">
      <SectionHead eyebrow="Getting started" title="How it works" />
      {/* The rule above each step turns into a rule beside it once the row
          becomes a column, so the sequence still reads as a track listing. */}
      <div className="grid grid-cols-4 max-[760px]:grid-cols-1">
        {STEPS.map((step) => (
          <div
            key={step.label}
            className="border-t-2 border-border pt-5 pr-4 max-[760px]:border-t-0 max-[760px]:border-l-2 max-[760px]:pt-0 max-[760px]:pl-5"
          >
            <Eyebrow tone="accent" className="mb-[10px]">
              {step.label}
            </Eyebrow>
            <p className="text-[0.95rem] text-text-dim">{step.body}</p>
          </div>
        ))}
      </div>
    </section>
  );
}
