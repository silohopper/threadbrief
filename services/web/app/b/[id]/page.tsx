"use client";
import * as React from "react";
import axios from "axios";
import Header from "../../../components/Header";
import { Container, Box, Typography, Chip, Button, Alert, Card, Divider } from "@mui/material";

type Brief = {
  id: string;
  share_url: string;
  title: string;
  overview: string;
  bullets: string[];
  why_it_matters?: string | null;
  meta: {
    source_type: string;
    mode: string;
    length: string;
    output_language: string;
  };
};

const API_BASE = process.env.NEXT_PUBLIC_API_BASE_URL || "http://localhost:8080";

export default function BriefPage({ params }: { params: { id: string } }) {
  const [brief, setBrief] = React.useState<Brief | null>(null);
  const [error, setError] = React.useState<string | null>(null);

  React.useEffect(() => {
    (async () => {
      try {
        const res = await axios.get(`${API_BASE}/v1/briefs/${params.id}`);
        setBrief(res.data);
      } catch (e: any) {
        setError(e?.response?.data?.detail || "Brief not found.");
      }
    })();
  }, [params.id]);

  return (
    <>
      <Header />
      <Container maxWidth="md" sx={{ py: 6 }}>
        {error && <Alert severity="error">{error}</Alert>}

        {brief && (
          <Card sx={{ p: 4 }}>
            <Box sx={{ display: "flex", justifyContent: "space-between", gap: 2, flexWrap: "wrap" }}>
              <Box sx={{ flex: 1, minWidth: 260 }}>
                <Typography variant="h4" fontWeight={900} gutterBottom>
                  {brief.title}
                </Typography>
                <Typography variant="body1" color="text.secondary">
                  {brief.overview}
                </Typography>
              </Box>

              <Box sx={{ display: "flex", gap: 1, flexWrap: "wrap", alignSelf: "flex-start" }}>
                <Chip label={brief.meta.source_type} />
                <Chip label={brief.meta.mode} />
                <Chip label={brief.meta.length} />
                <Chip label={brief.meta.output_language} />
              </Box>
            </Box>

            <Divider sx={{ my: 3 }} />

            <Typography variant="h6" fontWeight={800} sx={{ mb: 1 }}>
              Key points
            </Typography>
            <Box component="ul" sx={{ pl: 3, m: 0 }}>
              {brief.bullets.map((b, i) => (
                <li key={i}>
                  <Typography variant="body1">{b}</Typography>
                </li>
              ))}
            </Box>

            {brief.why_it_matters && (
              <>
                <Divider sx={{ my: 3 }} />
                <Typography variant="h6" fontWeight={800} sx={{ mb: 1 }}>
                  Why this matters
                </Typography>
                <Typography variant="body1">{brief.why_it_matters}</Typography>
              </>
            )}

            <Box sx={{ display: "flex", gap: 1.5, mt: 4, flexWrap: "wrap" }}>
              <Button
                variant="contained"
                onClick={() => navigator.clipboard.writeText(window.location.href)}
                sx={{ fontWeight: 700 }}
              >
                Copy link
              </Button>
              <Button
                variant="outlined"
                onClick={() =>
                  navigator.clipboard.writeText(
                    `${brief.title}

${brief.overview}

${brief.bullets.map((x) => `- ${x}`).join("\n")}${
                      brief.why_it_matters ? `

Why it matters:
${brief.why_it_matters}` : ""
                    }`
                  )
                }
              >
                Copy text
              </Button>
            </Box>
          </Card>
        )}
      </Container>
    </>
  );
}
