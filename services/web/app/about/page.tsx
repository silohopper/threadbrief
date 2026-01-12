import Header from "../../components/Header";
import { Container, Typography, Box, Card } from "@mui/material";

export default function AboutPage() {
  return (
    <>
      <Header />
      <Container maxWidth="md" sx={{ py: 6 }}>
        <Card sx={{ p: 4 }}>
          <Typography variant="h4" fontWeight={900} gutterBottom>
            About ThreadBrief
          </Typography>
          <Typography variant="body1" color="text.secondary" sx={{ mb: 2 }}>
            ThreadBrief is a demo-first tool that turns long videos and huge threads into structured briefs you can share.
          </Typography>

          <Typography variant="h6" fontWeight={800} sx={{ mt: 3, mb: 1 }}>
            Phase 0 limitations
          </Typography>
          <Typography variant="body1" color="text.secondary">
            YouTube transcripts are best-effort. If a transcript is not available, use Paste mode.
            Twitter/LinkedIn auto-fetch is intentionally not in v1.
          </Typography>
        </Card>
      </Container>
    </>
  );
}
