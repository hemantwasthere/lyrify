import { SectionHead } from "@/components/primitives";

const NOTES = [
  {
    title: "Lyrics that arrive on cue",
    body: "Every line is timed to the second. The current line is highlighted the moment it's sung, the next one waits dimmed just below — never a wall of static text.",
  },
  {
    title: "Follows you everywhere",
    body: "Stays on top of every desktop Space and every fullscreen app or game — no more alt-tabbing back to Spotify just to see what's playing.",
  },
  {
    title: "Resizes like it means it",
    body: "Shrink it down to a small now-playing card, or open it up to a full lyrics view — smooth the whole way, no flicker, no fixed size steps.",
  },
  {
    title: "Feels like it belongs on your Mac",
    body: "Real window behavior — drag, resize cursor, native close button, hover-revealed controls. Not a hacky floating box bolted onto the screen.",
  },
];

export function LinerNotes() {
  return (
    <section className="py-[clamp(40px,7vw,72px)]">
      <SectionHead eyebrow="Side A" title="What's actually on this record" />
      <div className="flex flex-col">
        {NOTES.map((note, i) => (
          <div
            key={note.title}
            className="grid grid-cols-[44px_1fr] gap-5 border-t border-border py-6 last:border-b"
          >
            <div className="pt-0.5 font-mono text-[0.85rem] text-accent">
              {String(i + 1).padStart(2, "0")}
            </div>
            <div>
              <h3 className="mb-1.5 text-[1.12rem]">{note.title}</h3>
              <p className="max-w-[56ch] text-text-dim">{note.body}</p>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}
