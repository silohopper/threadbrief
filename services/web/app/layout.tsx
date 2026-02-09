import * as React from "react";
import { Sora } from "next/font/google";
import { GoogleAnalytics } from "@next/third-parties/google";
import ThemeRegistry from "./theme/ThemeRegistry";

const sora = Sora({
  subsets: ["latin"],
  display: "swap",
  weight: ["300", "400", "500", "600", "700"],
});

export const metadata = {
  title: "ThreadBrief",
  description: "Turn long content into a clear brief.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  const gaId = process.env.NEXT_PUBLIC_GA_ID;
  return (
    <html lang="en">
      <body className={sora.className}>
        <ThemeRegistry>{children}</ThemeRegistry>
      </body>
      {gaId ? <GoogleAnalytics gaId={gaId} /> : null}
    </html>
  );
}
