# ThreadBrief — Repo Map (what each file does)

This document explains the purpose of each *source* file in the latest build, grouped by folder.


---

## Top level

- **`.gitignore`**
  - Git ignore rules. Should exclude build artifacts like `services/web/.next/`, Python `__pycache__/`, `.pyc`, `.DS_Store`, etc.

- **`README.md`**
  - Product overview + quickstart. High-level “what is ThreadBrief”, roadmap, and links to deeper docs.

---

## `bin/`

- **`bin/tools.sh`**
  - Convenience CLI for common dev tasks (compose up/down/logs/shell/lint/test/build).
  - Acts as the main “one command” interface so you don’t have to remember compose incantations.

---

## `docs/`

- **`docs/architecture.md`**
  - System overview: services (web + api), request flow, where YouTube transcript + LLM fitting happens, and what’s “in scope” for the demo MVP.

- **`docs/dev-flow.md`**
  - Local dev workflow and troubleshooting:
    - how to run the stack
    - common errors (ports, env vars, missing keys)
    - expected URLs (web, api, docs)

---

## `env/`

Environment-specific runtime config and orchestration.

### `env/dev/`

- **`env/dev/docker-compose.yml`**
  - Local two-service stack:
    - `api` (FastAPI via Uvicorn, hot reload)
    - `web` (Next.js dev server)
  - Mounts the service folders as volumes so edits on your machine reflect instantly in containers.
  - Exposes ports:
    - API: `8080`
    - Web: `3000`

- **`env/dev/.env.example`**
  - Template for required env vars. Copy to `.env` when onboarding a new machine.

- **`env/dev/.env`**
  - Local secrets/config (do **not** commit).
  - Typical values:
    - `GEMINI_API_KEY=...` (optional; if absent the API will generate a deterministic mock brief)
    - `CORS_ORIGINS=http://localhost:3000`
    - `RATE_LIMIT_PER_DAY=2`

### `env/stage/`

- **`env/stage/README.md`**
  - Notes for staging deployment config and expected variables/domains.

### `env/prod/`

- **`env/prod/README.md`**
  - Notes for production deployment config and expected variables/domains.

---

## `services/api/` (FastAPI)

Python API that:
1) accepts a YouTube URL or pasted text,  
2) optionally fetches a transcript,  
3) builds an LLM prompt,  
4) calls Gemini (or mock),  
5) parses the response into a structured “Brief”,  
6) stores it in memory for the demo.

### Entry + packaging

- **`services/api/Dockerfile`**
  - Container build for the API service (used by dev compose and deploy).

- **`services/api/requirements.txt`**
  - Runtime dependencies (FastAPI, Uvicorn, httpx, youtube-transcript-api, etc.).

- **`services/api/pyproject.toml`**
  - Tooling metadata (formatting/lint/test configuration, packaging hints). If you standardize on one dependency system later, this can become the source of truth.

- **`services/api/handler.py`**
  - AWS Lambda entrypoint using `Mangum`.
  - Wraps FastAPI app so API Gateway/Lambda proxy can invoke it.

### Application code (`services/api/app/`)

- **`services/api/app/__init__.py`**
  - Marks `app` as a package.

- **`services/api/app/main.py`**
  - FastAPI app factory:
    - registers CORS middleware
    - mounts routers (currently `briefs_router` under `/v1`)
    - exposes `/health`

- **`services/api/app/routers/__init__.py`**
  - Router package marker / shared exports.

- **`services/api/app/routers/briefs.py`**
  - **Main API surface**.
  - Defines endpoints:
    - `POST /v1/briefs` — create a brief from YouTube or pasted text
    - `GET /v1/briefs/{brief_id}` — fetch a stored brief (demo memory store)
  - Implements simple per-IP per-day rate limiting using the in-memory store.

- **`services/api/app/models.py`**
  - Pydantic request/response models:
    - `CreateBriefRequest` (source_type, source, mode, length, output_language)
    - `BriefMeta`, `Brief`

- **`services/api/app/settings.py`**
  - Loads env-driven settings (APP_ENV, CORS_ORIGINS, STORAGE_BACKEND, GEMINI_API_KEY, RATE_LIMIT_PER_DAY).

- **`services/api/app/storage.py`**
  - `MemoryStore` implementation:
    - stores briefs by `id`
    - tracks rate-limit counters per `(ip, day_key)`
  - Note: this is demo-only; production would move to Redis/Postgres.

- **`services/api/app/utils.py`**
  - Small helpers such as:
    - detecting YouTube URLs
    - extracting video IDs
    - cleaning pasted text (normalize whitespace, remove junk)

- **`services/api/app/youtube.py`**
  - Transcript fetch logic using `youtube_transcript_api`.
  - Wraps common failure modes into a `TranscriptError` with user-friendly messages.
  - Includes extra logging for hard-to-debug transcript fetch issues.

- **`services/api/app/llm.py`**
  - Builds the prompt and calls Gemini via HTTP (`httpx`) when `GEMINI_API_KEY` is set.
  - Provides `mock_brief()` for deterministic local/dev output when no key is present.
  - **Important:** In this build, the `mode_hint` line appears malformed (string quoting) and will throw a syntax error until fixed.

- **`services/api/app/parse.py`**
  - Parses “strict-ish” LLM output format into the `Brief` model:
    - reads `Title:`, `Overview:`, `Bullets:`, optional `WhyItMatters:`
  - Designed to be forgiving of minor formatting variations.

- **`services/api/app/tests/test_api.py`**
  - Basic API tests (smoke tests for endpoints and response shape).

---

## `services/web/` (Next.js + MUI)

Frontend UI that:
- lets users choose input type (YouTube URL or paste)
- selects mode/length/language
- calls the API to generate a brief
- supports share links at `/b/{id}`

### Config + tooling

- **`services/web/Dockerfile`**
  - Container build for the web service.

- **`services/web/package.json`**
  - Node deps + scripts (`dev`, `build`, `start`, lint).
  - Uses Next.js + React + Material UI + axios.

- **`services/web/next.config.mjs`**
  - Next config (app router, build settings).

- **`services/web/tsconfig.json`**
  - TypeScript configuration.

- **`services/web/eslint.config.mjs`**
  - Lint rules.

- **`services/web/next-env.d.ts`**
  - Next.js TypeScript type shims.

### App router pages (`services/web/app/`)

- **`services/web/app/layout.tsx`**
  - Root layout + metadata and wraps the app with MUI ThemeRegistry.

- **`services/web/app/page.tsx`**
  - Landing / main brief creation UI (the default route).

- **`services/web/app/login/page.tsx`**
  - Simple login page (demo scaffolding; can become admin gating later).

- **`services/web/app/my-briefs/page.tsx`**
  - “My briefs” page (likely showing saved/generated briefs in the demo).

- **`services/web/app/about/page.tsx`**
  - About page.

- **`services/web/app/b/[id]/page.tsx`**
  - Share page route:
    - loads a brief by id from the API
    - renders it in a shareable format

### UI components

- **`services/web/components/Header.tsx`**
  - Shared header / navigation UI.

- **`services/web/app/theme/ThemeRegistry.tsx`**
  - MUI theme + Next.js SSR/CSR styling integration (Emotion cache pattern).

---

## Build artifacts you should NOT commit

These commonly appear in zips/exports but should be removed/ignored:

- **`services/web/.next/`** — Next build output (regenerate via `npm run build`)
- **Python `__pycache__/` + `*.pyc`** — bytecode cache
- **`__MACOSX/` + `.DS_Store`** — macOS Finder metadata

If they’re in git history, add rules to `.gitignore` and delete them.

---

## Quick “where are the endpoints?”

Once the API is running:

- Swagger UI: `http://localhost:8080/docs`
- OpenAPI JSON: `http://localhost:8080/openapi.json`
- Health: `http://localhost:8080/health`

---

## Suggested README addition

Add this under “Docs” in `README.md`:

- `docs/architecture.md` — system overview
- `docs/dev-flow.md` — local workflow
- `docs/repo-map.md` — what each file does (this doc)
