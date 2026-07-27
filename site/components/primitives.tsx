import { downloadUrl } from "@/lib/release";

export function cx(...parts: Array<string | false | undefined>) {
  return parts.filter(Boolean).join(" ");
}

/**
 * The small mono caps label that opens most blocks.
 *
 * Colour is a `tone` rather than something to override through `className`:
 * two competing `text-*` utilities are resolved by their order in the compiled
 * stylesheet, not the order they are written in, so the accent variant would
 * win or lose by accident.
 */
export function Eyebrow({
  children,
  className,
  tone = "dim",
}: {
  children: React.ReactNode;
  className?: string;
  tone?: "dim" | "accent";
}) {
  return (
    <p
      className={cx(
        "font-mono text-[0.72rem] uppercase tracking-[0.14em]",
        tone === "accent" ? "text-accent" : "text-text-dim",
        className,
      )}
    >
      {children}
    </p>
  );
}

/** Mono body text, dimmed — version lines, requirements, install notes. */
export function Note({
  children,
  className,
  as: Tag = "p",
}: {
  children: React.ReactNode;
  className?: string;
  as?: "p" | "span";
}) {
  return (
    <Tag className={cx("font-mono text-[0.78rem] text-text-dim", className)}>
      {children}
    </Tag>
  );
}

export function DownloadButton() {
  return (
    <a
      href={downloadUrl}
      className="inline-block rounded-[10px] bg-accent px-[26px] py-[13px] font-body text-[0.95rem] font-semibold text-accent-ink transition-[transform,box-shadow] duration-150 ease-out hover:-translate-y-px hover:shadow-lift focus-visible:outline-2 focus-visible:outline-offset-[3px] focus-visible:outline-text"
    >
      Download for macOS
    </a>
  );
}

export function SectionHead({
  eyebrow,
  title,
}: {
  eyebrow: string;
  title: string;
}) {
  return (
    <div className="mb-9">
      <Eyebrow className="mb-[10px]">{eyebrow}</Eyebrow>
      <h2 className="text-[clamp(1.6rem,3vw,2.1rem)]">{title}</h2>
    </div>
  );
}
