import { LyrifyMark } from "@/components/LyrifyMark";

export function Header() {
  return (
    <header className="mx-auto flex max-w-[960px] items-center justify-between px-[clamp(20px,5vw,48px)] py-7">
      <div className="flex items-center gap-[10px] font-display text-[1.3rem] tracking-[0.01em]">
        <LyrifyMark className="size-7 shrink-0" />
        Lyrify
      </div>
      <a
        href="#download"
        className="rounded-full border border-border px-4 py-2 font-mono text-[0.78rem] transition-colors duration-200 hover:border-accent hover:text-accent focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
      >
        Download
      </a>
    </header>
  );
}
