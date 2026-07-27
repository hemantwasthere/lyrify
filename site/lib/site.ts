/** Identity and copy that more than one file needs to agree on. */
export const site = {
  url: "https://lyrify.hemant.lol",
  name: "Lyrify",
  title: "Lyrify — lyrics that keep up with the music",
  /**
   * Two descriptions, deliberately. The meta description names the product so
   * it reads as a sentence in a search result; the social one drops the name
   * because the card already shows it.
   */
  description:
    "Lyrify is a menu-bar companion for Spotify on Mac that floats a small, time-synced lyrics overlay over whatever you're doing.",
  socialDescription:
    "A menu-bar companion for Spotify on Mac that floats a small, time-synced lyrics overlay over whatever you're doing.",
  ogImageAlt: "Lyrify — a time-synced Spotify lyrics overlay for macOS",
  requirements: "macOS 14 Sonoma or later",
  author: {
    name: "Hemant",
    handle: "@hemantwasthere",
    x: "https://x.com/hemantwasthere",
    github: "https://github.com/hemantwasthere",
  },
} as const;

/** The two palettes, as the browser chrome sees them. */
export const themeColors = {
  dark: "#10201b",
  light: "#f2ece0",
} as const;
