import Header from "../../components/Header";
import { Container, Card, Typography, TextField, Box, List, ListItem, ListItemText, Divider } from "@mui/material";

export default function MyBriefsPage() {
  return (
    <>
      <Header />
      <Container maxWidth="md" sx={{ py: 6 }}>
        <Card sx={{ p: 4 }}>
          <Box sx={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 2, flexWrap: "wrap" }}>
            <Typography variant="h4" fontWeight={900}>
              My Briefs
            </Typography>
            <TextField size="small" placeholder="Search" sx={{ minWidth: 220 }} disabled />
          </Box>

          <Typography variant="body2" color="text.secondary" sx={{ mt: 1, mb: 3 }}>
            Phase 1 feature. This page becomes your saved brief vault once login is enabled.
          </Typography>

          <List>
            <ListItem>
              <ListItemText primary="How to Build a Timber Fence" secondary="YouTube · Insights · Brief · English" />
              <Typography variant="body2" color="text.secondary">2 minutes ago</Typography>
            </ListItem>
            <Divider />
            <ListItem>
              <ListItemText primary="Stripe Payment Retries Explained" secondary="Twitter · Insights · Brief · English" />
              <Typography variant="body2" color="text.secondary">Yesterday</Typography>
            </ListItem>
          </List>
        </Card>
      </Container>
    </>
  );
}
