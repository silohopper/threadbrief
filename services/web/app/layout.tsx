import * as React from "react";
import ThemeRegistry from "./theme/ThemeRegistry";

export const metadata = {
  title: "ThreadBrief",
  description: "Turn long content into a clear brief.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <ThemeRegistry>{children}</ThemeRegistry>
      </body>
    </html>
  );
}
