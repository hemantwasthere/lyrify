import type { Metadata, Viewport } from "next";
import localFont from "next/font/local";

import { site, themeColor } from "@/lib/site";
import "./globals.css";

/**
 * Fraunces, subset to the two cuts the page uses, self-hosted. These were
 * base64'd into a `<style>` block before, which is what made the old page a
 * 122 KB HTML file — the fonts were 77 KB of it, re-downloaded with the markup
 * on every visit and never cached separately. next/font emits them as
 * hashed files, preloads them, and generates the `@font-face` rules.
 */
const fraunces = localFont({
  src: [
    { path: "../fonts/fraunces-600-normal.woff2", weight: "600", style: "normal" },
    { path: "../fonts/fraunces-500-italic.woff2", weight: "500", style: "italic" },
  ],
  variable: "--font-fraunces",
  display: "swap",
  fallback: ["Georgia", "ui-serif", "serif"],
});

export const metadata: Metadata = {
  metadataBase: new URL(site.url),
  title: site.title,
  description: site.description,
  applicationName: site.name,
  authors: [{ name: site.author.name, url: site.author.x }],
  alternates: { canonical: "/" },
  appleWebApp: { title: site.name },
  // No `icons` key: `app/favicon.ico`, `app/icon.png` and `app/apple-icon.png`
  // generate their own link tags, under a content hash. Naming the files here
  // would pin them to fixed `/public` URLs and hand browsers a favicon they can
  // cache past a rebrand — which is exactly what kept the green disc onscreen.
  robots: {
    index: true,
    follow: true,
    "max-image-preview": "large",
    "max-snippet": -1,
    "max-video-preview": -1,
  },
  openGraph: {
    type: "website",
    siteName: site.name,
    locale: "en_US",
    title: site.title,
    description: site.socialDescription,
    url: "/",
    images: [
      {
        url: "/og-image.png",
        type: "image/png",
        width: 1200,
        height: 630,
        alt: site.ogImageAlt,
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    site: site.author.handle,
    creator: site.author.handle,
    title: site.title,
    description: site.socialDescription,
    images: [{ url: "/og-image.png", alt: site.ogImageAlt }],
  },
};

/**
 * One colour, unconditionally — the page renders cream whatever the OS is set
 * to, so a media-matched pair would only ever describe a theme that no longer
 * exists and paint the address bar a colour found nowhere on the page.
 */
export const viewport: Viewport = { themeColor };

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={fraunces.variable}>
      <body>{children}</body>
    </html>
  );
}
