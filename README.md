# ThreadBrief

Turn long content into a clear brief.

ThreadBrief distills:
- **YouTube videos** (when captions/transcripts are available)
- **Pasted threads** (Twitter/X, LinkedIn, Reddit, email, forums)

…into a **structured brief** with:
- **Insights vs Summary**
- **Conciseness slider**
- **Output language (translate)**
- **Bitly-style share link** (`/b/{id}`)

This repo is a **demo-first** proof-of-work project:
- Minimal scope
- Cheap to run
- Easy to deploy/teardown in AWS
- Designed to be a portfolio-quality cloud deployment
- Reusable as a scaffolding for future projects with a frontend and fastapi.

---

## Mobile-first or responsive?

**Responsive-first** (works great on mobile + desktop).  
The UI is designed with MUI components and a centered layout that scales down cleanly to phones.

---

## Domain

- Production domain: **threadbrief.com**
- Suggested staging domain: **stage.threadbrief.com** (optional)

---

## Roadmap (phase order)

1. ✅ Phase 0 — Demo MVP (ship)
2. 🧠 Phase 1.5 — Smarter Distillation
3. 🔐 Phase 1 — Login + My Briefs
4. 🖼 Phase 2 — Visual Slides
5. 🔁 Phase 2.5 — Flow Diagrams
6. 🎧 Phase 3 — Voice Narration

---

## Phase 0 Scope (locked)

### Inputs
- YouTube URL
- Paste text (threads / posts / comments)

### Controls
- Mode: **Insights** | Summary
- Length: TL;DR | Brief | Detailed
- Output language: translate the **brief output** (not full transcript)

### Outputs
- Structured brief (text)
- Share link: `https://threadbrief.com/b/{shortId}`

### Safety
- Rate limit: **2 briefs/day/IP** (demo-safe)

---

## Tech stack

### Frontend
- Next.js (App Router) + TypeScript
- MUI (Material UI) + Emotion

### Backend
- FastAPI (local dev)
- Deployed on ECS Fargate (Lambda handler is optional/unused)
- Gemini API (optional; mock mode works without keys)
- Storage: in-memory (dev) or DynamoDB (optional later)

### Local dev
- Docker Compose (web + api)
- One command scripts via `bin/tools.sh`

---

## Repo structure

```
.
├─ bin/
│  └─ tools.sh
├─ env/
│  ├─ dev/
│  │  ├─ docker-compose.yml
│  │  └─ .env.example
│  ├─ stage/
│  └─ prod/
├─ services/
│  ├─ web/          # Next.js app
│  └─ api/          # FastAPI API service
└─ README.md
```

---

## Quickstart (local)

1) Copy env file:

```bash
cp env/dev/.env.example env/dev/.env
```

2) Start everything:

```bash
sh bin/tools.sh dev up
```

3) Open:
- Web: http://localhost:3000
- API: http://localhost:8080/docs

---

## Useful commands

```bash
sh bin/tools.sh dev down          # stop containers
sh bin/tools.sh dev logs web      # tail logs
sh bin/tools.sh dev logs api
sh bin/tools.sh dev shell web     # shell into container
sh bin/tools.sh dev shell api
sh bin/tools.sh dev test          # run api tests
sh bin/tools.sh dev test-youtube  # run YouTube integration test
sh bin/tools.sh dev test-gemini   # run Gemini integration test
sh bin/tools.sh dev lint          # lint (web + api)
```

## Deploy (AWS)
Deployment scripts and Terraform live in `infra/`. See [infra/README.md](infra/README.md)
for the exact staging/prod steps.
That guide includes a suggested IAM policy if you want tighter permissions than
`AdministratorAccess`.

---

## API (Phase 0)

### Optional: YouTube audio fallback (local Whisper)
YouTube transcripts use YouTube captions first. If none exist, the API falls back
to downloading audio with `yt-dlp` and transcribing locally with the Whisper CLI.

Environment variables (optional):
- `WHISPER_PATH` (override path to `whisper` binary)
- `WHISPER_MODEL` (default: `base`)
- `WHISPER_LANGUAGE` (default: `en`)
- `YTDLP_PATH` / `YOUTUBEDL_PATH` (override downloader path)

Note: the Whisper dependency is intentionally excluded from CI installs. It is
installed in Docker via `services/api/requirements-whisper.txt`.

### POST `/v1/briefs`

Request:
```json
{
  "source_type": "youtube" | "paste",
  "source": "https://youtube.com/watch?v=..." | "pasted text ...",
  "mode": "insights" | "summary",
  "length": "tldr" | "brief" | "detailed",
  "output_language": "en"
}
```

Response:
```json
{
  "id": "3fA9kQ",
  "share_url": "http://localhost:3000/b/3fA9kQ",
  "title": "How to Build a Timber Fence",
  "overview": "…",
  "bullets": ["…", "…"],
  "why_it_matters": "…",
  "meta": {
    "source_type": "youtube",
    "mode": "insights",
    "length": "brief",
    "output_language": "en"
  }
}
```

### GET `/v1/briefs/{id}`

Returns the saved brief for the share page.

---

## Gemini API setup (optional)

Phase 0 runs without keys (mock mode).  
To enable real generation, set:

- `GEMINI_API_KEY=...`

in `env/dev/.env`.

---

## Notes

- YouTube transcripts are best-effort. If a transcript isn't available, use Paste mode.
- Twitter/LinkedIn scraping is intentionally not in v1.
- Login + My Briefs comes later (Phase 1).

---

## License

MIT

## Dev flow
See `docs/dev-flow.md` for the exact local workflow and troubleshooting.
