# Architecture (Phase 0)

- Web (Next.js + MUI) calls API (FastAPI) at `/v1/briefs`.
- API generates structured brief using Gemini (or mock if no API key).
- Brief stored in memory (Phase 0). Later: DynamoDB + user accounts.
- Share page is `/b/{id}` and fetches the brief from API.

## Lambda readiness
`services/api/handler.py` exposes a Mangum handler so the same FastAPI app can run on AWS Lambda later.
