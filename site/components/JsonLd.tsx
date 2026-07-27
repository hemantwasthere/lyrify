import { downloadUrl, release } from "@/lib/release";
import { site } from "@/lib/site";

const graph = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "WebSite",
      "@id": `${site.url}/#website`,
      url: site.url,
      name: site.name,
      description: site.socialDescription,
      inLanguage: "en",
      publisher: { "@id": `${site.url}/#person` },
    },
    {
      "@type": "Person",
      "@id": `${site.url}/#person`,
      name: site.author.name,
      url: site.author.x,
      sameAs: [site.author.x, site.author.github],
    },
    {
      "@type": "SoftwareApplication",
      "@id": `${site.url}/#app`,
      name: site.name,
      url: site.url,
      description: site.description,
      applicationCategory: "MultimediaApplication",
      applicationSubCategory: "Music",
      operatingSystem: site.requirements,
      processorRequirements: "Apple Silicon or Intel",
      softwareVersion: release.version,
      downloadUrl,
      softwareHelp: release.repo,
      screenshot: `${site.url}/og-image.png`,
      image: `${site.url}/og-image.png`,
      author: { "@id": `${site.url}/#person` },
      isAccessibleForFree: true,
      offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
    },
  ],
};

export function JsonLd() {
  return (
    <script
      type="application/ld+json"
      // Escaped so a `<` in any value can't close the script tag early.
      dangerouslySetInnerHTML={{
        __html: JSON.stringify(graph).replace(/</g, "\\u003c"),
      }}
    />
  );
}
