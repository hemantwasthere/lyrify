import type { Metadata, Viewport } from "next";
import localFont from "next/font/local";

import { site, themeColors } from "@/lib/site";
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
  icons: {
    icon: [
      { url: "/favicon-32.png", sizes: "32x32", type: "image/png" },
      { url: "/favicon-16.png", sizes: "16x16", type: "image/png" },
    ],
    apple: "/apple-touch-icon.png",
  },
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
 * The static page pinned the browser chrome to the dark palette even when the
 * page itself rendered light, so the address bar clashed with the background.
 */
export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: dark)", color: themeColors.dark },
    { media: "(prefers-color-scheme: light)", color: themeColors.light },
  ],
};

export default function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en" className={fraunces.variable}>
      <body>{children}</body>
    </html>
  );
}
