import type { MetadataRoute } from "next";

import { release } from "@/lib/release";
import { site } from "@/lib/site";

export default function sitemap(): MetadataRoute.Sitemap {
  return [
    {
      url: site.url,
      // The release date, not the build date: the page's content changes when
      // a version ships, and `new Date()` would claim a fresh edit on every
      // unrelated redeploy.
      lastModified: new Date(release.date),
      changeFrequency: "weekly",
      priority: 1,
    },
  ];
}
