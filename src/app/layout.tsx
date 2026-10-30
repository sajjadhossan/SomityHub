import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "SomitiPro",
  description: "সমিতি ব্যবস্থাপনা, হিসাব ও সদস্য সেবা"
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="bn">
      <body>{children}</body>
    </html>
  );
}
