"use client";
import * as React from "react";
import Link from "next/link";
import Image from "next/image";
import { AppBar, Toolbar, Box, Button } from "@mui/material";

export default function Header() {
  return (
    <AppBar
      position="static"
      elevation={0}
      sx={{ borderBottom: "1px solid", borderColor: "divider", bgcolor: "common.white", color: "text.primary" }}
    >
      <Toolbar sx={{ gap: 2, minHeight: { xs: 64, sm: 72 }, py: { xs: 1, sm: 1.5 } }}>
        <Box sx={{ position: "relative", width: { xs: 120, sm: 140, md: 160 }, height: { xs: 40, sm: 48, md: 56 } }}>
          <Image
            src="/logo.jpg"
            alt="ThreadBrief logo"
            fill
            sizes="(max-width: 600px) 120px, (max-width: 900px) 160px, 200px"
            style={{ objectFit: "contain" }}
            priority
          />
        </Box>
        <Box sx={{ flex: 1 }} />
        <Button component={Link} href="/about" color="inherit">
          About
        </Button>
        <Button
          component="a"
          href="https://github.com/silohopper/threadbrief"
          target="_blank"
          rel="noreferrer"
          color="inherit"
        >
          GitHub
        </Button>
      </Toolbar>
    </AppBar>
  );
}
