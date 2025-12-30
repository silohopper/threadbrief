#!/bin/bash
# ThreadBrief tools.sh
# Usage:
#   sh bin/tools.sh dev up
#   sh bin/tools.sh dev down
#   sh bin/tools.sh dev logs web
#   sh bin/tools.sh dev shell api
#   sh bin/tools.sh dev lint
#   sh bin/tools.sh dev test

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV="${1:-}"
CMD="${2:-}"
ARG="${3:-}"

# Binaries
DOCKER_BIN="$(command -v docker || true)"
COMPOSE_BIN="$(command -v docker-compose || true)"

compose() {
  local env="$1"
  if [ -z "$COMPOSE_BIN" ]; then
    # docker compose (plugin) fallback
    $DOCKER_BIN compose -f "$ROOT_DIR/env/$env/docker-compose.yml" "$@"
  else
    $COMPOSE_BIN -f "$ROOT_DIR/env/$env/docker-compose.yml" "$@"
  fi
}

help() {
  cat <<'EOF'
SYNOPSIS
  sh bin/tools.sh <env> <command> [service]

ENV
  dev | stage | prod

COMMANDS (dev)
  up                docker compose up -d
  down              docker compose down
  restart           down then up
  logs <svc>        tail logs (web|api)
  shell <svc>       shell into container (web|api)
  ps                docker compose ps
  lint              lint web + api
  test              run api tests
  format            format web + api
  build             build web + api images

COMMANDS (stage/prod)
  up                placeholder (Terraform coming next)
  down              placeholder (Terraform coming next)
  deploy            placeholder
  destroy           placeholder

EXAMPLES
  sh bin/tools.sh dev up
  sh bin/tools.sh dev logs api
  sh bin/tools.sh dev shell web
EOF
}

if [ -z "$ENV" ] || [ -z "$CMD" ]; then
  help
  exit 1
fi

case "$ENV" in
  dev|stage|prod) ;;
  *) echo "Unknown env: $ENV"; help; exit 1 ;;
esac

if [ "$ENV" != "dev" ]; then
  case "$CMD" in
    up|down|deploy|destroy)
      echo "[INFO] $ENV/$CMD not implemented yet (Terraform module next)."
      echo "       Domain: threadbrief.com"
      exit 0
      ;;
    *) echo "Unknown command for $ENV: $CMD"; help; exit 1 ;;
  esac
fi

# DEV commands
case "$CMD" in
  up)
    echo "[DEV] Starting containers..."
    compose dev up -d --build
    ;;
  down)
    echo "[DEV] Stopping containers..."
    compose dev down
    ;;
  restart)
    echo "[DEV] Restarting containers..."
    compose dev down
    compose dev up -d --build
    ;;
  ps)
    compose dev ps
    ;;
  logs)
    if [ -z "${ARG:-}" ]; then echo "Missing service for logs (web|api)"; exit 1; fi
    compose dev logs -f "$ARG"
    ;;
  shell)
    if [ -z "${ARG:-}" ]; then echo "Missing service for shell (web|api)"; exit 1; fi
    compose dev exec "$ARG" sh
    ;;
  lint)
    echo "[DEV] Linting API..."
    compose dev exec -T api sh -lc "ruff check . && mypy app"
    echo "[DEV] Linting WEB..."
    compose dev exec -T web sh -lc "npm run lint"
    ;;
  format)
    echo "[DEV] Formatting API..."
    compose dev exec -T api sh -lc "ruff format ."
    echo "[DEV] Formatting WEB..."
    compose dev exec -T web sh -lc "npm run format || true"
    ;;
  test)
    echo "[DEV] Running API tests..."
    compose dev exec -T api sh -lc "pytest -q"
    ;;
  build)
    echo "[DEV] Building images..."
    compose dev build
    ;;
  *)
    echo "Unknown command: $CMD"
    help
    exit 1
    ;;
esac
