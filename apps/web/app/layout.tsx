import type { Metadata } from "next";
import { DM_Sans, Fraunces } from "next/font/google";
import "./globals.css";
import "./adjustments.css";

const sans = DM_Sans({ subsets: ["latin"], variable: "--sans" });
const serif = Fraunces({ subsets: ["latin"], variable: "--serif" });

export const metadata: Metadata = { title: "Kairos — Know when it's time to start", description: "An adaptive personal execution agent." };

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body className={`${sans.variable} ${serif.variable}`}>{children}</body></html>;
}
