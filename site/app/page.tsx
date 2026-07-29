import { DemoVideo } from "@/components/DemoVideo";
import { DownloadSection } from "@/components/DownloadSection";
import { Footer } from "@/components/Footer";
import { Header } from "@/components/Header";
import { Hero } from "@/components/Hero";
import { HowItWorks } from "@/components/HowItWorks";
import { JsonLd } from "@/components/JsonLd";
import { LinerNotes } from "@/components/LinerNotes";

export default function Home() {
  return (
    <>
      <JsonLd />
      <Header />
      <div className="mx-auto max-w-[960px] px-[clamp(20px,5vw,48px)]">
        <Hero />
        <DemoVideo />
        <LinerNotes />
        <HowItWorks />
        <DownloadSection />
        <Footer />
      </div>
    </>
  );
}
