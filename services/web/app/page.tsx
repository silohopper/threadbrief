"use client";
import * as React from "react";
import axios from "axios";
import Header from "../components/Header";
import {
  Container,
  Box,
  Typography,
  Card,
  Tabs,
  Tab,
  TextField,
  FormControl,
  InputLabel,
  Select,
  MenuItem,
  Slider,
  Button,
  Alert,
  Checkbox,
  FormControlLabel,
  Chip,
  Divider,
} from "@mui/material";

type SourceType = "youtube" | "paste";
type ModeType = "insights" | "summary";
type LengthType = "tldr" | "brief" | "detailed";

type Brief = {
  id: string;
  share_url: string;
  title: string;
  overview: string;
  bullets: string[];
  why_it_matters?: string | null;
  meta: {
    source_type: SourceType;
    mode: ModeType;
    length: LengthType;
    output_language: string;
  };
};

const API_BASE = process.env.NEXT_PUBLIC_API_BASE_URL || "http://localhost:8080";
const UI_MAX_VIDEO_MINUTES = 180;
const TYPING_LINES = [
  "Turn long content into a clear brief.",
  "Paste your YouTube and summarize its contents.",
  "Get the highlights of a long social thread.",
];

function lengthFromSlider(v: number): LengthType {
  return v === 0 ? "tldr" : v === 2 ? "detailed" : "brief";
}
function sliderFromLength(l: LengthType): number {
  return l === "tldr" ? 0 : l === "detailed" ? 2 : 1;
}

export default function HomePage() {
  const [tab, setTab] = React.useState<SourceType>("youtube");
  const [youtubeUrl, setYoutubeUrl] = React.useState("");
  const [pasteText, setPasteText] = React.useState("");
  const [cleanFormatting, setCleanFormatting] = React.useState(true);

  const [mode, setMode] = React.useState<ModeType>("insights");
  const [outputLanguage, setOutputLanguage] = React.useState("en");
  const [length, setLength] = React.useState<LengthType>("brief");
  const [videoDurationMinutes, setVideoDurationMinutes] = React.useState<number | null>(null);

  const [loading, setLoading] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);
  const [brief, setBrief] = React.useState<Brief | null>(null);
  const [typingIndex, setTypingIndex] = React.useState(0);
  const [typingCharIndex, setTypingCharIndex] = React.useState(0);
  const [typingIsDeleting, setTypingIsDeleting] = React.useState(false);

  React.useEffect(() => {
    const currentLine = TYPING_LINES[typingIndex];
    let timeout: ReturnType<typeof setTimeout> | undefined;

    if (!typingIsDeleting) {
      if (typingCharIndex < currentLine.length) {
        timeout = setTimeout(() => setTypingCharIndex((count) => count + 1), 40);
      } else {
        timeout = setTimeout(() => setTypingIsDeleting(true), 2200);
      }
    } else if (typingCharIndex > 0) {
      timeout = setTimeout(() => setTypingCharIndex((count) => count - 1), 20);
    } else {
      setTypingIsDeleting(false);
      setTypingIndex((index) => (index + 1) % TYPING_LINES.length);
    }

    return () => {
      if (timeout) {
        clearTimeout(timeout);
      }
    };
  }, [typingCharIndex, typingIndex, typingIsDeleting]);

  const typedLine = TYPING_LINES[typingIndex].slice(0, typingCharIndex);

  const canSubmit =
    (tab === "youtube" && youtubeUrl.trim().length > 8) ||
    (tab === "paste" && pasteText.trim().length >= 200);

  async function fetchVideoDuration(url: string) {
    const res = await axios.get(`${API_BASE}/v1/video-meta`, {
      params: { url },
      timeout: 120000,
    });
    const minutes = Number(res.data?.duration_minutes);
    if (Number.isFinite(minutes)) {
      setVideoDurationMinutes(minutes);
      return minutes;
    }
    return null;
  }

  async function onGenerate() {
    setError(null);
    setBrief(null);
    setLoading(true);
    try {
      if (tab === "youtube") {
        const minutes = await fetchVideoDuration(youtubeUrl.trim());
        if (minutes && minutes > UI_MAX_VIDEO_MINUTES) {
          setError(`Video is ${minutes.toFixed(1)} minutes. Max shown in UI is ${UI_MAX_VIDEO_MINUTES} minutes.`);
          return;
        }
      }
      const payload = {
        source_type: tab,
        source: tab === "youtube" ? youtubeUrl.trim() : (cleanFormatting ? pasteText : pasteText).trim(),
        mode,
        length,
        output_language: outputLanguage,
      };
      const res = await axios.post(`${API_BASE}/v1/briefs`, payload, { timeout: 900000 });
      setBrief(res.data);
    } catch (e: any) {
      const msg =
        e?.response?.data?.detail ||
        e?.message ||
        "Could not generate a brief right now. Try again.";
      setError(msg);
      // UX helper: if transcript error, nudge to paste
      if (typeof msg === "string" && msg.toLowerCase().includes("transcript")) {
        // nothing auto here; user decides
      }
    } finally {
      setLoading(false);
    }
  }

  const lengthLabel = length === "tldr" ? "TL;DR: 3–5 key points" : length === "detailed" ? "Detailed: 8–12 key points" : "Brief: 5–8 key points";

  return (
    <>
      <Header />
      <Container maxWidth="md" sx={{ py: 6 }}>
        <Box sx={{ textAlign: "center", mb: 4 }}>
          <Typography variant="h3" fontWeight={800} gutterBottom sx={{ minHeight: { xs: "2.6em", sm: "2.2em" } }}>
            {typedLine}
            <Box
              component="span"
              sx={{
                display: "inline-block",
                ml: 0.5,
                width: "0.7ch",
                animation: "blink 1s steps(1) infinite",
                "@keyframes blink": {
                  "0%": { opacity: 1 },
                  "50%": { opacity: 0 },
                  "100%": { opacity: 1 },
                },
              }}
            >
              |
            </Box>
          </Typography>
        </Box>

        <Card sx={{ p: 3, mb: 3 }}>
          <Tabs value={tab} onChange={(_, v) => setTab(v)} sx={{ mb: 2 }}>
            <Tab value="youtube" label="YouTube Video" />
            <Tab value="paste" label="Paste Thread" />
          </Tabs>

          {tab === "youtube" ? (
            <Box sx={{ mb: 2 }}>
              <TextField
                fullWidth
                label="YouTube URL"
                value={youtubeUrl}
                onChange={(e) => setYoutubeUrl(e.target.value)}
                placeholder="https://www.youtube.com/watch?v=..."
              />
              <Typography variant="caption" color="text.secondary" sx={{ display: "block", mt: 1 }}>
                Works when subtitles/transcripts are available. Max {UI_MAX_VIDEO_MINUTES} minutes.
                {videoDurationMinutes ? ` Detected: ${videoDurationMinutes.toFixed(1)} min.` : ""}
              </Typography>
            </Box>
          ) : (
            <Box sx={{ mb: 2 }}>
              <TextField
                fullWidth
                multiline
                minRows={6}
                label="Paste text (thread / post / comments)"
                value={pasteText}
                onChange={(e) => setPasteText(e.target.value)}
                placeholder="Tip: paste the main post + top replies. You don’t need everything."
              />
              <FormControlLabel
                control={<Checkbox checked={cleanFormatting} onChange={(e) => setCleanFormatting(e.target.checked)} />}
                label="Clean formatting automatically"
                sx={{ mt: 1 }}
              />
            </Box>
          )}

          <Box sx={{ display: "flex", gap: 2, flexWrap: "wrap", alignItems: "center", mb: 2 }}>
            <FormControl sx={{ minWidth: 160 }}>
              <InputLabel>Mode</InputLabel>
              <Select value={mode} label="Mode" onChange={(e) => setMode(e.target.value as ModeType)}>
                <MenuItem value="insights">Insights</MenuItem>
                <MenuItem value="summary">Summary</MenuItem>
              </Select>
            </FormControl>

            <FormControl sx={{ minWidth: 200 }}>
              <InputLabel>Output language</InputLabel>
              <Select value={outputLanguage} label="Output language" onChange={(e) => setOutputLanguage(e.target.value)}>
                <MenuItem value="en">English</MenuItem>
                <MenuItem value="es">Spanish</MenuItem>
                <MenuItem value="fr">French</MenuItem>
                <MenuItem value="de">German</MenuItem>
                <MenuItem value="pt">Portuguese</MenuItem>
                <MenuItem value="it">Italian</MenuItem>
                <MenuItem value="nl">Dutch</MenuItem>
                <MenuItem value="hi">Hindi</MenuItem>
                <MenuItem value="id">Indonesian</MenuItem>
                <MenuItem value="ja">Japanese</MenuItem>
              </Select>
            </FormControl>

            <Box sx={{ flex: 1, minWidth: 240 }}>
              <Typography variant="body2" fontWeight={600} sx={{ mb: 0.5 }}>
                Length
              </Typography>
              <Slider
                value={sliderFromLength(length)}
                onChange={(_, v) => setLength(lengthFromSlider(v as number))}
                step={1}
                marks
                min={0}
                max={2}
              />
              <Typography variant="caption" color="text.secondary">
                {lengthLabel}
              </Typography>
            </Box>
          </Box>

          <Button
            fullWidth
            variant="contained"
            size="large"
            disabled={!canSubmit || loading}
            onClick={onGenerate}
            sx={{ py: 1.5, fontWeight: 700 }}
          >
            {loading ? "Generating…" : "Generate Brief"}
          </Button>

          <Typography variant="caption" color="text.secondary" sx={{ display: "block", textAlign: "center", mt: 1.5 }}>
            Demo is rate-limited (100 briefs per day).
          </Typography>
        </Card>

        {error && (
          <Alert severity="warning" sx={{ mb: 3 }}>
            {error}
          </Alert>
        )}

        {brief && (
          <Card sx={{ p: 3 }}>
            <Box sx={{ display: "flex", alignItems: "flex-start", gap: 2, mb: 2, flexWrap: "wrap" }}>
              <Box sx={{ flex: 1, minWidth: 240 }}>
                <Typography variant="h5" fontWeight={800}>
                  {brief.title} <Typography component="span" color="text.secondary" fontWeight={500}>(Brief)</Typography>
                </Typography>
                <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
                  {brief.overview}
                </Typography>
              </Box>

              <Box sx={{ display: "flex", gap: 1, flexWrap: "wrap" }}>
                <Chip label={brief.meta.source_type} />
                <Chip label={brief.meta.mode} />
                <Chip label={brief.meta.length} />
                <Chip label={brief.meta.output_language} />
              </Box>
            </Box>

            <Divider sx={{ mb: 2 }} />

            <Box component="ul" sx={{ pl: 3, m: 0 }}>
              {brief.bullets.slice(0, 6).map((b, i) => (
                <li key={i}>
                  <Typography variant="body1">{b}</Typography>
                </li>
              ))}
            </Box>

            <Box sx={{ display: "flex", gap: 1.5, mt: 3, flexWrap: "wrap" }}>
              <Button variant="contained" href={`/b/${brief.id}`} sx={{ fontWeight: 700 }}>
                Open share link
              </Button>
              <Button
                variant="outlined"
                onClick={() => navigator.clipboard.writeText(`${window.location.origin}/b/${brief.id}`)}
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
