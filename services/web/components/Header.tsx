"use client";
import * as React from "react";
import Link from "next/link";
import { AppBar, Toolbar, Typography, Box, Button } from "@mui/material";

export default function Header() {
  return (
    <AppBar position="static" elevation={0} sx={{ borderBottom: "1px solid", borderColor: "divider" }}>
      <Toolbar sx={{ gap: 2 }}>
        <Box sx={{ display: "flex", alignItems: "center", gap: 1 }}>
          <Typography variant="h6" fontWeight={700}>
            ThreadBrief
          </Typography>
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
