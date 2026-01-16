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
RED="\033[31m"
RESET="\033[0m"

# Binaries
DOCKER_BIN="$(command -v docker || true)"
DOCKER_COMPOSE_BIN="$(command -v docker-compose || true)"
HAS_DOCKER_COMPOSE_PLUGIN=false

if [ -n "$DOCKER_BIN" ] && "$DOCKER_BIN" compose version >/dev/null 2>&1; then
  HAS_DOCKER_COMPOSE_PLUGIN=true
fi

compose() {
  local env="$1"
  shift

  if [ "$HAS_DOCKER_COMPOSE_PLUGIN" = true ]; then
    "$DOCKER_BIN" compose -f "$ROOT_DIR/env/$env/docker-compose.yml" "$@"
    return
  fi

  if [ -n "$DOCKER_COMPOSE_BIN" ]; then
    "$DOCKER_COMPOSE_BIN" -f "$ROOT_DIR/env/$env/docker-compose.yml" "$@"
    return
  fi

  echo "docker compose not found. Install Docker Desktop or docker-compose." >&2
  exit 1
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
  test-youtube      run YouTube integration test (requires network)
  test-gemini       run Gemini integration test (requires GEMINI_API_KEY)
  format            format web + api
  build             build web + api images

COMMANDS (stage/prod)
  up                placeholder (Terraform coming next)
  down              placeholder (Terraform coming next)
  deploy            placeholder
  destroy           placeholder
  resync            import existing AWS resources into state
  unlock <lock_id>  force-unlock Terraform state
  logs <svc>        tail CloudWatch logs (api|web)
  elb               show ELB + target health info

EXAMPLES
  sh bin/tools.sh dev up
  sh bin/tools.sh dev logs api
  sh bin/tools.sh dev shell web
  sh bin/tools.sh stage up
  sh bin/tools.sh stage dns
  sh bin/tools.sh stage deploy
  sh bin/tools.sh stage down
  sh bin/tools.sh stage resync
  sh bin/tools.sh stage unlock <lock_id>
  sh bin/tools.sh stage logs api
  sh bin/tools.sh stage elb
EOF
}

tf_init_select_workspace() {
  local env="$1"
  local tf_dir="$2"

  terraform -chdir="$tf_dir" init
  if terraform -chdir="$tf_dir" workspace select "$env" >/dev/null 2>&1; then
    return
  fi
  terraform -chdir="$tf_dir" workspace new "$env" >/dev/null
}

tf_resync_state() {
  local env="$1"
  local tf_dir="$2"

  tf_init_select_workspace "$env" "$tf_dir"

  try_import() {
    local addr="$1"
    local id="$2"
    terraform -chdir="$tf_dir" import "$addr" "$id" >/dev/null 2>&1 || true
  }

  try_import aws_ecr_repository.api "threadbrief-$env-api"
  try_import aws_ecr_repository.web "threadbrief-$env-web"
  try_import aws_iam_role.task "threadbrief-$env-task"
  try_import aws_iam_role.task_execution "threadbrief-$env-task-exec"
  try_import aws_iam_service_linked_role.ecs "ecs.amazonaws.com"
}

if [ -z "$ENV" ] || [ -z "$CMD" ]; then
  printf "%bNot enough arguments. Usage: sh bin/tools.sh <env> <command> [service]%b\n" "$RED" "$RESET"
  if [ -z "$ENV" ]; then
    printf "%bMissing environment. Expected: dev | stage | prod.%b\n" "$RED" "$RESET"
  else
    printf "%bMissing command for environment '%s'.%b\n" "$RED" "$ENV" "$RESET"
  fi
  echo
  help
  exit 1
fi

case "$ENV" in
  dev|stage|prod) ;;
  *) echo "Unknown env: $ENV"; help; exit 1 ;;
esac

if [ "$ENV" != "dev" ]; then
  case "$CMD" in
    up)
      echo "[$ENV] Terraform apply..."
      tf_init_select_workspace "$ENV" "$ROOT_DIR/infra/terraform"
      if [ "$ENV" != "prod" ]; then
        slr_arn="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/aws-service-role/ecs.amazonaws.com/AWSServiceRoleForECS"
        terraform -chdir="$ROOT_DIR/infra/terraform" import -var-file="$ROOT_DIR/infra/terraform/envs/$ENV.tfvars" aws_iam_service_linked_role.ecs "$slr_arn" >/dev/null 2>&1 || true
      fi
      if [ "${RESYNC:-}" = "1" ]; then
        echo "[$ENV] Resyncing existing resources into state..."
        tf_resync_state "$ENV" "$ROOT_DIR/infra/terraform"
      fi
      if ! terraform -chdir="$ROOT_DIR/infra/terraform" apply -var-file="$ROOT_DIR/infra/terraform/envs/$ENV.tfvars" -auto-approve; then
        echo "[$ENV] Apply failed; attempting resync and retry..." >&2
        tf_resync_state "$ENV" "$ROOT_DIR/infra/terraform"
        terraform -chdir="$ROOT_DIR/infra/terraform" apply -var-file="$ROOT_DIR/infra/terraform/envs/$ENV.tfvars" -auto-approve
      fi
      exit 0
      ;;
    dns)
      tf_init_select_workspace "$ENV" "$ROOT_DIR/infra/terraform"
      terraform -chdir="$ROOT_DIR/infra/terraform" output route53_name_servers
      exit 0
      ;;
    cert)
      tf_init_select_workspace "$ENV" "$ROOT_DIR/infra/terraform"
      if ! terraform -chdir="$ROOT_DIR/infra/terraform" output acm_validation_records >/dev/null 2>&1; then
        terraform -chdir="$ROOT_DIR/infra/terraform" apply \
          -var-file="$ROOT_DIR/infra/terraform/envs/$ENV.tfvars" \
          -target=aws_acm_certificate.this
      fi
      terraform -chdir="$ROOT_DIR/infra/terraform" output acm_validation_records
      exit 0
      ;;
    down|destroy)
      echo "[$ENV] Terraform destroy..."
      tf_init_select_workspace "$ENV" "$ROOT_DIR/infra/terraform"
      AWS_REGION="${AWS_REGION:-ap-southeast-2}"
      ecr_targets=()
      if aws ecr describe-repositories --region "$AWS_REGION" --repository-names "threadbrief-$ENV-api" >/dev/null 2>&1; then
        ecr_targets+=(-target=aws_ecr_repository.api)
      fi
      if aws ecr describe-repositories --region "$AWS_REGION" --repository-names "threadbrief-$ENV-web" >/dev/null 2>&1; then
        ecr_targets+=(-target=aws_ecr_repository.web)
      fi
      if [ "${#ecr_targets[@]}" -gt 0 ]; then
        terraform -chdir="$ROOT_DIR/infra/terraform" apply -var-file="$ROOT_DIR/infra/terraform/envs/$ENV.tfvars" "${ecr_targets[@]}" -auto-approve
      fi
      if [ "$ENV" != "prod" ]; then
        terraform -chdir="$ROOT_DIR/infra/terraform" state rm aws_iam_service_linked_role.ecs >/dev/null 2>&1 || true
      fi
      terraform -chdir="$ROOT_DIR/infra/terraform" destroy -var-file="$ROOT_DIR/infra/terraform/envs/$ENV.tfvars" -auto-approve
      exit 0
      ;;
    resync)
      echo "[$ENV] Resyncing existing resources into state..."
      tf_resync_state "$ENV" "$ROOT_DIR/infra/terraform"
      exit 0
      ;;
    unlock)
      if [ -z "${ARG:-}" ]; then
        echo "Missing lock id for unlock."
        exit 1
      fi
      terraform -chdir="$ROOT_DIR/infra/terraform" force-unlock "$ARG"
      exit 0
      ;;
    logs)
      if [ -z "${ARG:-}" ]; then
        echo "Missing service for logs (api|web)."
        exit 1
      fi
      if [ "$ARG" != "api" ] && [ "$ARG" != "web" ]; then
        echo "Unknown service for logs: $ARG (expected api|web)."
        exit 1
      fi
      aws logs tail "/ecs/threadbrief/$ENV/$ARG" --since 10m
      exit 0
      ;;
    elb)
      lb_name="threadbrief-$ENV"
      lb_arn="$(aws elbv2 describe-load-balancers --names "$lb_name" --query "LoadBalancers[0].LoadBalancerArn" --output text)"
      echo "Load balancer: $lb_name"
      echo "ARN: $lb_arn"
      aws elbv2 describe-load-balancer-attributes \
        --load-balancer-arn "$lb_arn" \
        --query "Attributes[?Key=='idle_timeout.timeout_seconds']"
      aws elbv2 describe-listeners --load-balancer-arn "$lb_arn" \
        --query "Listeners[].{Port:Port,Protocol:Protocol,Default:DefaultActions[0].Type}"
      api_tg="$(aws elbv2 describe-target-groups --names "threadbrief-$ENV-api" --query "TargetGroups[0].TargetGroupArn" --output text)"
      web_tg="$(aws elbv2 describe-target-groups --names "threadbrief-$ENV-web" --query "TargetGroups[0].TargetGroupArn" --output text)"
      echo "API target group: $api_tg"
      aws elbv2 describe-target-health --target-group-arn "$api_tg"
      echo "WEB target group: $web_tg"
      aws elbv2 describe-target-health --target-group-arn "$web_tg"
      exit 0
      ;;
    deploy)
      echo "[$ENV] Deploying images to ECR and updating ECS services..."
      AWS_REGION="${AWS_REGION:-ap-southeast-2}"
      TAG="${TAG:-latest}"
      TF_DIR="$ROOT_DIR/infra/terraform"
      if ! docker info >/dev/null 2>&1; then
        echo "Docker daemon not running. Start Docker Desktop and retry." >&2
        exit 1
      fi
      VARS_ARGS=(-var-file="$TF_DIR/envs/$ENV.tfvars")
      if [ -f "$TF_DIR/envs/$ENV.local.tfvars" ]; then
        VARS_ARGS+=(-var-file="$TF_DIR/envs/$ENV.local.tfvars")
      fi
      COOKIES_FILE="$ROOT_DIR/env/$ENV/cookies.txt"
      if [ ! -f "$COOKIES_FILE" ]; then
        COOKIES_FILE="$ROOT_DIR/env/dev/cookies.txt"
      fi
      if [ -f "$COOKIES_FILE" ]; then
        export TF_VAR_ytdlp_cookies="$(cat "$COOKIES_FILE")"
        VARS_ARGS+=(-var "ytdlp_cookies=$TF_VAR_ytdlp_cookies")
      fi
      PROXY_FILE="$ROOT_DIR/env/$ENV/proxy.txt"
      if [ ! -f "$PROXY_FILE" ]; then
        PROXY_FILE="$ROOT_DIR/env/dev/proxy.txt"
      fi
      if [ -f "$PROXY_FILE" ]; then
        export TF_VAR_ytdlp_proxy="$(tr -d '\n' < "$PROXY_FILE")"
        VARS_ARGS+=(-var "ytdlp_proxy=$TF_VAR_ytdlp_proxy")
      fi

      if [ "${RESYNC:-}" = "1" ]; then
        echo "[$ENV] Resyncing existing resources into state..."
        tf_resync_state "$ENV" "$TF_DIR"
      else
        tf_init_select_workspace "$ENV" "$TF_DIR"
      fi
      terraform -chdir="$TF_DIR" apply "${VARS_ARGS[@]}" -auto-approve

      api_repo="$(terraform -chdir="$TF_DIR" output -raw api_ecr_url)"
      web_repo="$(terraform -chdir="$TF_DIR" output -raw web_ecr_url)"
      cluster_name="$(terraform -chdir="$TF_DIR" output -raw ecs_cluster_name)"
      api_service="$(terraform -chdir="$TF_DIR" output -raw api_service_name)"
      web_service="$(terraform -chdir="$TF_DIR" output -raw web_service_name)"
      api_domain="$(terraform -chdir="$TF_DIR" output -raw api_domain)"

      aws ecr get-login-password --region "$AWS_REGION" \
        | docker login --username AWS --password-stdin "${api_repo%/*}"

      echo "[BUILD] API image"
      docker build -t "$api_repo:$TAG" "$ROOT_DIR/services/api"
      docker push "$api_repo:$TAG"

      echo "[BUILD] WEB image"
      docker build -t "$web_repo:$TAG" \
        --build-arg NEXT_PUBLIC_API_BASE_URL="https://${api_domain}" \
        -f "$ROOT_DIR/services/web/Dockerfile.prod" \
        "$ROOT_DIR/services/web"
      docker push "$web_repo:$TAG"

      echo "[DEPLOY] Updating ECS services"
      aws ecs update-service --cluster "$cluster_name" --service "$api_service" --force-new-deployment > /dev/null
      aws ecs update-service --cluster "$cluster_name" --service "$web_service" --force-new-deployment > /dev/null
      echo "[DONE] Deploy triggered for $ENV (tag=$TAG)"
      exit 0
      ;;
    *) echo "Unknown command for $ENV: $CMD"; help; exit 1 ;;
  esac
fi

# DEV commands
case "$CMD" in
  up)
    echo "[DEV] Starting containers..."
    if [ -f "$ROOT_DIR/env/dev/cookies.txt" ]; then
      export YTDLP_COOKIES="$(cat "$ROOT_DIR/env/dev/cookies.txt")"
    fi
    if [ -f "$ROOT_DIR/env/dev/proxy.txt" ]; then
      export YTDLP_PROXY="$(tr -d '\n' < "$ROOT_DIR/env/dev/proxy.txt")"
    fi
    compose dev up -d --build
    ;;
  down)
    echo "[DEV] Stopping containers..."
    compose dev down
    ;;
  restart)
    echo "[DEV] Restarting containers..."
    compose dev down
    if [ -f "$ROOT_DIR/env/dev/cookies.txt" ]; then
      export YTDLP_COOKIES="$(cat "$ROOT_DIR/env/dev/cookies.txt")"
    fi
    if [ -f "$ROOT_DIR/env/dev/proxy.txt" ]; then
      export YTDLP_PROXY="$(tr -d '\n' < "$ROOT_DIR/env/dev/proxy.txt")"
    fi
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
  test-youtube)
    echo "[DEV] Running YouTube integration test..."
    proxy_env=""
    if [ -f "$ROOT_DIR/env/dev/proxy.txt" ]; then
      proxy_env="YTDLP_PROXY=$(tr -d '\n' < "$ROOT_DIR/env/dev/proxy.txt")"
    fi
    compose dev exec -T api sh -lc "$proxy_env YOUTUBE_INTEGRATION=1 pytest -q -k youtube -s"
    ;;
  test-gemini)
    echo "[DEV] Running Gemini integration test..."
    compose dev exec -T api sh -lc "GEMINI_INTEGRATION=1 pytest -q -k gemini -s"
    ;;
  build)
    echo "[DEV] Building images..."
    compose dev build
    ;;
  *)
    echo "Unknown dev command: $CMD"
    help
    exit 1
    ;;
esac
