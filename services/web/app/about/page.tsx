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
            Phase 1 limitations
          </Typography>
          <Typography variant="body1" color="text.secondary">
            Some YouTube videos don’t have captions, so those won’t work here yet. In that case, use Paste mode.
            For now, paste text from Twitter or LinkedIn instead of a link.
          </Typography>
        </Card>
      </Container>
    </>
  );
}
