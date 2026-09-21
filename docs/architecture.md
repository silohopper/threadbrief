# Architecture

- Web (Next.js + MUI) is a static export served from S3 + CloudFront. It
  calls the API's Lambda Function URL directly at `/v1/briefs` — no server,
  no SSR.
- API is a container-image Lambda (`services/api/handler.py`, Mangum
  adapter) behind a Function URL, not API Gateway — brief generation can
  take minutes for long videos, and API Gateway hard-caps integration
  timeouts at ~30s. A Function URL inherits Lambda's own timeout instead.
- API generates a structured brief using Gemini (or a deterministic mock if
  no API key is set).
- Briefs and per-IP daily rate limits are stored in DynamoDB
  (`services/api/app/storage.py`), with TTLs so old data expires on its own.
  (In-memory storage doesn't work here: different Lambda invocations can run
  on different execution environments, so a brief saved by one request
  could 404 when its share link was opened from another.)
- Share page is `/b?id={id}` (a query param, not a path segment — Next's
  static export can't resolve an arbitrary dynamic path segment without a
  server) and fetches the brief from the API.

No ECS, no ALB, no always-on compute. See `infra/README.md` for the full
deploy story and cost breakdown.
