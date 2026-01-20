# ThreadBrief — Development TODO / Roadmap

This document tracks the phased development plan for ThreadBrief.

The project is intentionally shipped in **1 (Demo MVP)** first.
All later phases are optional, incremental, and can be completed over time.

Primary goals:
- Serve as **proof of work** for full-stack AI app delivery
- Act as a **boilerplate** for launching future apps (frontend + backend + infra)
- Support a clean public GitHub showcase

---

## ✅ Phase 1 — Demo MVP (SHIPPED / IN PROGRESS)

**Status:** ✅ Primary focus  
**Purpose:** End-to-end working demo (frontend, backend, infra shape)

### Core Features
- [x] Paste text or YouTube URL input
- [x] Generate structured brief (LLM or deterministic mock)
- [x] Shareable brief page `/b/{id}`
- [x] API endpoints:
  - [x] `POST /v1/briefs`
  - [x] `GET /v1/briefs/{id}`
  - [x] `/health`
  - [x] `/docs` (Swagger)
- [x] YouTube transcript fetch with graceful fallback
- [x] In-memory storage (demo only)
- [x] Local dev via Docker Compose
- [x] One-command run via `bin/tools.sh`

### Polish / Showcase Tasks
- [ ] Fix known syntax issue in `services/api/app/llm.py`
- [ ] Remove build artifacts from repo (`.next`, `__pycache__`, macOS files)
- [ ] Tighten README quickstart section
- [ ] Add 1–2 screenshots or GIFs to README
- [ ] Confirm `.gitignore` covers all generated files

---

## 🧠 Phase 1.5 — Smarter Distillation

**Status:** Planned  
**Purpose:** Improve output quality without adding accounts or persistence

### Tasks
- [ ] Improved prompt templates (modes)
  - [ ] Executive summary
  - [ ] Key takeaways
  - [ ] Action items
- [ ] Chunking for long transcripts
- [ ] Iterative summarization pass
- [ ] Stronger output formatting constraints
- [ ] More forgiving parser with validation
- [ ] Optional timestamp references for YouTube sources

---

## 🔐 Phase 1 — Login + My Briefs

**Status:** Deferred  
**Purpose:** Turn demo into a usable personal tool

### Tasks
- [ ] Authentication (magic link or basic auth)
- [ ] User table + brief ownership
- [ ] Persistent storage (SQLite/Postgres)
- [ ] “My Briefs” page
- [ ] Per-user rate limiting
- [ ] Optional public/private brief toggle

---

## 🖼 Phase 2 — Visual Slides

**Status:** Planned  
**Purpose:** High-impact showcase feature

### Tasks
- [ ] Convert brief → slide structure
- [ ] Render slide preview in UI
- [ ] Export slides (PDF or PPTX)
- [ ] Consistent slide theming

---

## 🔁 Phase 2.5 — Flow Diagrams

**Status:** Planned  
**Purpose:** Visual reasoning from text

### Tasks
- [ ] Generate Mermaid diagrams
  - [ ] Flowchart
  - [ ] Sequence diagram
  - [ ] Mind map
- [ ] Render diagrams in UI
- [ ] Export diagram as SVG/PNG

---

## 🎧 Phase 3 — Voice Narration

**Status:** Planned  
**Purpose:** Turn briefs into audio briefings

### Tasks
- [ ] Generate narration script from brief
- [ ] Text-to-speech (Piper / Polly / ElevenLabs)
- [ ] Audio playback in UI
- [ ] Downloadable audio file

---

## 🚧 Future / Nice-to-Have

- [ ] Django version of this boilerplate (separate repo)
- [ ] Redis-backed rate limiting
- [ ] Background jobs for long transcripts
- [ ] Webhook / API client examples
- [ ] CI pipeline (lint, test, build)

---

## Philosophy

- Phase 1 is intentionally **complete and shippable**
- Later phases are **modular upgrades**
- Repo should always build, run, and demo cleanly
