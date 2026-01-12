# Contributing

## How to run (local)
- `cp env/dev/.env.example env/dev/.env`
- `sh bin/tools.sh dev up`
- Web: http://localhost:3000
- API docs: http://localhost:8080/docs

## Branch naming
- Use `<type>/<short-desc>` (lowercase, hyphenated).
- Examples: `feat/yt-fallback`, `fix/parse-bullets`, `chore/ci-ruff`

## Commit style
- Conventional Commits: `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`
- Optional scope: `feat(api): add transcript fallback`

## How to test
- API unit tests: `cd services/api && pytest`
- YouTube integration test: `sh bin/tools.sh dev test-youtube` (requires network + ffmpeg/whisper in Docker)
- Lint: `ruff check services/api`
