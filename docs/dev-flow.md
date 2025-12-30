# Dev flow (local)

This is the "do this every time" guide for ThreadBrief Phase 0.

## Prereqs
- Docker Desktop (running)
- Git

## 1) First run (from repo root)

```bash
cp env/dev/.env.example env/dev/.env
sh bin/tools.sh dev up
```

Open:
- Web: http://localhost:3000
- API Swagger: http://localhost:8080/docs
- Health: http://localhost:8080/health

## 2) Run a full end-to-end test (no API key)
This works in **mock mode** (no Gemini key needed):

1. Open the web UI
2. Choose **Paste Thread**
3. Paste 200+ chars and click **Generate Brief**
4. Click **Open share link** and verify `/b/{id}` loads

## 3) Enable real Gemini output (optional)
Edit `env/dev/.env`:

```bash
GEMINI_API_KEY=your_key_here
```

Restart:

```bash
sh bin/tools.sh dev restart
```

## 4) Useful commands

```bash
sh bin/tools.sh dev logs api
sh bin/tools.sh dev logs web
sh bin/tools.sh dev shell api
sh bin/tools.sh dev shell web
sh bin/tools.sh dev down
```

## 5) Common issues & fixes

### Web loads but generate fails
- Check API is up: http://localhost:8080/health
- Check CORS in `env/dev/.env` (CORS_ORIGINS should include http://localhost:3000)

### "Daily limit reached"
- Demo rate limit is 2/day/IP (Phase 0). Change in `env/dev/.env`:
  - `RATE_LIMIT_PER_DAY=999` for dev if you want.

### YouTube transcript errors
- Many videos do not expose transcripts.
- Use Paste mode for those.

### Port conflicts (3000 or 8080 already used)
- Stop other services using those ports, or change ports in `env/dev/docker-compose.yml`.

## Notes
- Phase 0 stores briefs in memory. Restarting containers clears saved briefs.
- Login/My Briefs comes in Phase 1.
