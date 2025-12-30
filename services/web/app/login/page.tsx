import Header from "../../components/Header";
import { Container, Card, Typography, TextField, Button } from "@mui/material";

export default function LoginPage() {
  return (
    <>
      <Header />
      <Container maxWidth="sm" sx={{ py: 6 }}>
        <Card sx={{ p: 4 }}>
          <Typography variant="h4" fontWeight={900} gutterBottom>
            Welcome back
          </Typography>
          <Typography variant="body1" color="text.secondary" sx={{ mb: 3 }}>
            Sign in to view and manage your saved briefs.
          </Typography>

          <TextField fullWidth label="Email" placeholder="Enter your email" sx={{ mb: 2 }} />
          <Button fullWidth variant="contained" size="large" disabled sx={{ py: 1.5, fontWeight: 700 }}>
            Continue with Magic Link (Phase 1)
          </Button>

          <Typography variant="caption" color="text.secondary" sx={{ display: "block", mt: 2, textAlign: "center" }}>
            Not available in demo mode yet.
          </Typography>
        </Card>
      </Container>
    </>
  );
}
