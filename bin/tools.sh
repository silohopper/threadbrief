#!/bin/bash
# -----------------------------------------------------------------------------
# ThreadBrief tools.sh
#
# This is the "one script to rule them all" for:
#   - Local dev (Docker Compose)
#   - Stage/Prod infra (Terraform + AWS CLI)
#   - Deployment (build images, push to ECR, restart ECS)
#
# Why it exists:
#   You run simple commands like:
#     sh bin/tools.sh dev up
#     sh bin/tools.sh prod up
#     sh bin/tools.sh prod deploy
#
# And it handles all the messy differences between environments.
# -----------------------------------------------------------------------------

set -euo pipefail
# -e : exit immediately if a command fails (prevents silent broken states)
# -u : treat unset variables as errors (prevents typos becoming "empty strings")
# -o pipefail : if any part of a piped command fails, the whole pipe fails

# Enable verbose execution ONLY for prod.
# This prints each command before it runs so you can see what it's doing.
[ "${1:-}" = "prod" ] && set -x

# Resolve the project root directory (folder that contains env/, infra/, services/, etc)
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Parse CLI args:
#   ENV = dev|stage|prod
#   CMD = command like up/down/deploy/logs/etc
#   ARG = optional third argument (usually service name like web/api)
ENV="${1:-}"
CMD="${2:-}"
ARG="${3:-}"

# Pretty colors for error messages (only used in a few spots)
RED="\033[31m"
RESET="\033[0m"

# -----------------------------------------------------------------------------
# Detect whether Docker + docker compose is available
# -----------------------------------------------------------------------------
DOCKER_BIN="$(command -v docker || true)"
DOCKER_COMPOSE_BIN="$(command -v docker-compose || true)"
HAS_DOCKER_COMPOSE_PLUGIN=false

# Newer Docker uses: "docker compose" (plugin)
# Older setups might have: "docker-compose" (separate binary)
if [ -n "$DOCKER_BIN" ] && "$DOCKER_BIN" compose version >/dev/null 2>&1; then
  HAS_DOCKER_COMPOSE_PLUGIN=true
fi

# -----------------------------------------------------------------------------
# compose <env> <docker compose args...>
#
# This wrapper chooses the right compose command automatically:
#   - If "docker compose" exists, use that
#   - Else if "docker-compose" exists, use that
#   - Else error out
#
# It also pins the correct compose file:
#   env/<env>/docker-compose.yml
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# help()
# Prints usage and command list
# -----------------------------------------------------------------------------
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
  up                terraform apply (creates/updates infra)
  down              terraform destroy (tears down infra)
  deploy            build/push images to ECR + restart ECS services
  destroy           alias of down
  plan              terraform plan with correct var-file
  status            show terraform state/lock status
  tail              tail terraform logs for the last up/down action
  zoneid            show Route53 hosted zone IDs for domain_name
  api-test [url]    POST /v1/briefs and print response/timings
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
  sh bin/tools.sh stage plan
  sh bin/tools.sh stage status
  sh bin/tools.sh stage tail
  sh bin/tools.sh stage resync
  sh bin/tools.sh stage unlock <lock_id>
  sh bin/tools.sh stage logs api
  sh bin/tools.sh stage elb
EOF
}

# -----------------------------------------------------------------------------
# Terraform helpers
# -----------------------------------------------------------------------------

# tf_init_select_workspace <env> <tf_dir>
#
# Terraform uses "workspaces" to maintain separate state for dev/stage/prod.
# This function ensures:
#   - terraform init has run
#   - workspace exists and is selected
tf_init_select_workspace() {
  local env="$1"
  local tf_dir="$2"

  terraform -chdir="$tf_dir" init

  # If workspace exists, select it. If not, create it.
  if terraform -chdir="$tf_dir" workspace select "$env" >/dev/null 2>&1; then
    return
  fi
  terraform -chdir="$tf_dir" workspace new "$env" >/dev/null
}

# tf_log_path <env> <action> <tf_dir>
#
# Writes Terraform output to a timestamped log file so you can inspect later.
tf_log_path() {
  local env="$1"
  local action="$2"
  local tf_dir="$3"
  local log_dir="$tf_dir/logs"
  mkdir -p "$log_dir"
  echo "$log_dir/${env}-${action}-$(date +%Y%m%d-%H%M%S).log"
}

# -----------------------------------------------------------------------------
# tf_resync_state <env> <tf_dir>
#
# "Resync" imports existing AWS resources into Terraform state.
#
# Why do we need this?
# Terraform gets angry if it tries to create something that already exists
# (example: existing SG / existing ECR repo / existing target group).
#
# For prod especially, you sometimes have leftovers or you created stuff once,
# and Terraform state doesn't know about it yet. This function tries to import
# the common resources so Terraform will "adopt" them instead of duplicating.
# -----------------------------------------------------------------------------
tf_resync_state() {
  local env="$1"
  local tf_dir="$2"

  tf_init_select_workspace "$env" "$tf_dir"
  AWS_REGION="${AWS_REGION:-ap-southeast-2}"

  # try_import <terraform_resource_address> <aws_id>
  # Import is "best effort": ignore errors so the script keeps going.
  try_import() {
    local addr="$1"
    local id="$2"
    terraform -chdir="$tf_dir" import "$addr" "$id" >/dev/null 2>&1 || true
  }

  # ---------------------------------------------------------------------------
  # MINIMAL FIX: Prevent Route53 hosted-zone duplication.
  #
  # Problem you hit:
  #   Running "prod up" was creating NEW hosted zones in Route53 (duplicates).
  #
  # Root cause:
  #   Terraform only knows what’s in its state.
  #   If a hosted zone exists in AWS but NOT in Terraform state, Terraform may
  #   decide it needs to "create" one (boom, new zone).
  #
  # Fix approach:
  #   If a zone already exists, IMPORT it into terraform state BEFORE apply.
  #
  # NOTE 1:
  #   This uses resource address "aws_route53_zone.this".
  #   If your Terraform resource has a different name, change it.
  #
  # NOTE 2 (important for later):
  #   AWS can have both PUBLIC and PRIVATE zones with the same name.
  #   If you ever create a private zone, this query might grab the wrong one.
  #   If duplicates happen again, filter for Config.PrivateZone==false.
  # ---------------------------------------------------------------------------
  if [ "$env" = "prod" ]; then
    # -------------------------------------------------------------------------
    # ROUTE53 DUPLICATE ZONE AUTO-SELECTION (stubborn issue)
    #
    # We kept hitting a loop where "prod up" created a *new* hosted zone for
    # threadbrief.com, even though one already existed. Root cause: Terraform
    # can only reuse a hosted zone if it is imported into state, and AWS returns
    # the "first match" when multiple public zones share the same name.
    #
    # Fix: if multiple public zones exist, pick the one with the highest
    # ResourceRecordSetCount (the zone with real records) and reuse it. We still
    # log a warning so duplicates can be cleaned up later.
    # -------------------------------------------------------------------------
    hz_lines="$(aws route53 list-hosted-zones-by-name \
      --dns-name threadbrief.com \
      --query "HostedZones[?Name=='threadbrief.com.' && Config.PrivateZone==\`false\`].[Id,ResourceRecordSetCount]" \
      --output text 2>/dev/null || true)"
    hz_id=""
    hz_count=0
    hz_lines_count=0
    if [ -n "$hz_lines" ] && [ "$hz_lines" != "None" ]; then
      hz_lines_count="$(printf "%s\n" "$hz_lines" | wc -l | tr -d ' ')"
      while IFS=$'\t' read -r id count; do
        if [ -n "$count" ] && [ "$count" -ge "$hz_count" ]; then
          hz_count="$count"
          hz_id="$id"
        fi
      done <<< "$hz_lines"
    fi
    if [ -n "${ROUTE53_ZONE_ID:-}" ]; then
      hz_id="$ROUTE53_ZONE_ID"
    elif [ "$hz_lines_count" -gt 1 ]; then
      echo "Error: multiple public Route53 zones found for threadbrief.com. Set ROUTE53_ZONE_ID to the one you want." >&2
      exit 1
    fi
    # -------------------------------------------------------------------------
    # IMPORT EXISTING ZONE
    #
    # If the hosted zone exists, import it into Terraform state before apply.
    # This ensures prod reuses the same zone and prevents new zones.
    # Note: resource address is counted now, so we import [0].
    # -------------------------------------------------------------------------
    if [ -n "$hz_id" ] && [ "$hz_id" != "None" ]; then
      # AWS returns hosted zone ID like "/hostedzone/Z123..."
      # Terraform import expects "Z123..."
      hz_id="${hz_id#/hostedzone/}"
      try_import aws_route53_zone.this[0] "$hz_id"
    fi
  fi
  # ---------------------------------------------------------------------------

  # Find default VPC ID (this script assumes you're using the default VPC)
  vpc_id="$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text 2>/dev/null || true)"

  # If we have a VPC, look for the ALB security group we expect by name:
  # "threadbrief-<env>-alb"
  if [ -n "$vpc_id" ] && [ "$vpc_id" != "None" ]; then
    sg_id="$(aws ec2 describe-security-groups --filters Name=group-name,Values="threadbrief-$env-alb" Name=vpc-id,Values="$vpc_id" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)"
    if [ -n "$sg_id" ] && [ "$sg_id" != "None" ]; then
      try_import aws_security_group.alb "$sg_id"
    fi
  fi

  # CloudWatch log groups (ECS tasks write logs to these)
  # We import them if they exist to prevent Terraform trying to recreate.
  for log_group in "/ecs/threadbrief/$env/api" "/ecs/threadbrief/$env/web"; do
    lg_name="$(aws logs describe-log-groups --log-group-name-prefix "$log_group" --query "logGroups[?logGroupName=='$log_group']|[0].logGroupName" --output text 2>/dev/null || true)"
    if [ -n "$lg_name" ] && [ "$lg_name" != "None" ]; then
      if [ "$log_group" = "/ecs/threadbrief/$env/api" ]; then
        try_import aws_cloudwatch_log_group.api "$log_group"
      else
        try_import aws_cloudwatch_log_group.web "$log_group"
      fi
    fi
  done

  # ALB import (load balancer)
  lb_arn="$(aws elbv2 describe-load-balancers --names "threadbrief-$env" --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || true)"
  if [ -n "$lb_arn" ] && [ "$lb_arn" != "None" ]; then
    try_import aws_lb.this "$lb_arn"
  fi

  # Target groups import (ALB forwards to these)
  api_tg_arn="$(aws elbv2 describe-target-groups --names "threadbrief-$env-api" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || true)"
  if [ -n "$api_tg_arn" ] && [ "$api_tg_arn" != "None" ]; then
    try_import aws_lb_target_group.api "$api_tg_arn"
  fi

  web_tg_arn="$(aws elbv2 describe-target-groups --names "threadbrief-$env-web" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || true)"
  if [ -n "$web_tg_arn" ] && [ "$web_tg_arn" != "None" ]; then
    try_import aws_lb_target_group.web "$web_tg_arn"
  fi

  # ECR repos (where Docker images live)
  try_import aws_ecr_repository.api "threadbrief-$env-api"
  try_import aws_ecr_repository.web "threadbrief-$env-web"

  # IAM roles (ECS task role and execution role)
  try_import aws_iam_role.task "threadbrief-$env-task"
  try_import aws_iam_role.task_execution "threadbrief-$env-task-exec"

  # ECS service-linked role (AWS-managed role ECS needs)
  slr_account_id="$(aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
  if [ -n "$slr_account_id" ] && [ "$slr_account_id" != "None" ]; then
    slr_arn="arn:aws:iam::${slr_account_id}:role/aws-service-role/ecs.amazonaws.com/AWSServiceRoleForECS"
    try_import aws_iam_service_linked_role.ecs "$slr_arn"
  fi
}

# -----------------------------------------------------------------------------
# Argument validation
# -----------------------------------------------------------------------------
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

# Only allow these env values
case "$ENV" in
  dev|stage|prod) ;;
  *) echo "Unknown env: $ENV"; help; exit 1 ;;
esac

# -----------------------------------------------------------------------------
# Stage/Prod commands (Terraform/AWS)
#
# Any env != dev goes through this path.
# -----------------------------------------------------------------------------
if [ "$ENV" != "dev" ]; then
  case "$CMD" in
    up)
      # Creates/updates infrastructure via Terraform
      echo "[$ENV] Terraform apply..."
      tf_init_select_workspace "$ENV" "$ROOT_DIR/infra/terraform"

      vars_args=(-var-file="$ROOT_DIR/infra/terraform/envs/$ENV.tfvars")
      if [ -n "${ROUTE53_ZONE_ID:-}" ]; then
        vars_args+=(-var "route53_zone_id=$ROUTE53_ZONE_ID")
      fi

      # Prod gets special handling:
      #   - import existing resources into Terraform state before apply
      if [ "$ENV" = "prod" ]; then
        echo "[$ENV] Importing existing resources into state..."
        tf_resync_state "$ENV" "$ROOT_DIR/infra/terraform"
      else
        # For stage, import the ECS service linked role (some accounts already have it)
        slr_arn="arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/aws-service-role/ecs.amazonaws.com/AWSServiceRoleForECS"
        terraform -chdir="$ROOT_DIR/infra/terraform" import -var-file="$ROOT_DIR/infra/terraform/envs/$ENV.tfvars" aws_iam_service_linked_role.ecs "$slr_arn" >/dev/null 2>&1 || true
      fi

      # Optional manual resync (RESYNC=1 sh bin/tools.sh prod up)
      if [ "${RESYNC:-}" = "1" ]; then
        echo "[$ENV] Resyncing existing resources into state..."
        tf_resync_state "$ENV" "$ROOT_DIR/infra/terraform"
      fi

      # Log the entire terraform apply output
      log_path="$(tf_log_path "$ENV" "up" "$ROOT_DIR/infra/terraform")"

      # Run terraform apply; if it fails, try resync and retry once
      if ! terraform -chdir="$ROOT_DIR/infra/terraform" apply "${vars_args[@]}" -auto-approve 2>&1 | tee "$log_path"; then
        echo "[$ENV] Apply failed; attempting resync and retry..." >&2
        tf_resync_state "$ENV" "$ROOT_DIR/infra/terraform"
        terraform -chdir="$ROOT_DIR/infra/terraform" apply "${vars_args[@]}" -auto-approve 2>&1 | tee -a "$log_path"
      fi

      echo "[$ENV] Terraform log: $log_path"
      exit 0
      ;;

    dns)
      # Prints the Route53 name servers Terraform created/uses
      tf_init_select_workspace "$ENV" "$ROOT_DIR/infra/terraform"
      terraform -chdir="$ROOT_DIR/infra/terraform" output route53_name_servers
      exit 0
      ;;

    cert)
      # For ACM certificates, you often need validation records.
      # This prints out the CNAME validation records Terraform expects.
      tf_init_select_workspace "$ENV" "$ROOT_DIR/infra/terraform"
      vars_args=(-var-file="$ROOT_DIR/infra/terraform/envs/$ENV.tfvars")
      if [ -n "${ROUTE53_ZONE_ID:-}" ]; then
        vars_args+=(-var "route53_zone_id=$ROUTE53_ZONE_ID")
      fi
      if ! terraform -chdir="$ROOT_DIR/infra/terraform" output acm_validation_records >/dev/null 2>&1; then
        terraform -chdir="$ROOT_DIR/infra/terraform" apply \
          "${vars_args[@]}" \
          -target=aws_acm_certificate.this
      fi
      terraform -chdir="$ROOT_DIR/infra/terraform" output acm_validation_records
      exit 0
      ;;

    zoneid)
      # Show Route53 hosted zone IDs for the domain in envs/<ENV>.tfvars.
      domain_name="$(awk -F'=' '/^domain_name/ {gsub(/[[:space:]\"]/, "", $2); print $2; exit}' "$ROOT_DIR/infra/terraform/envs/$ENV.tfvars")"
      if [ -z "$domain_name" ]; then
        domain_name="threadbrief.com"
      fi
      aws route53 list-hosted-zones-by-name \
        --dns-name "$domain_name" \
        --query "HostedZones[?Name=='${domain_name}.']|[].[Id,Name,Config.PrivateZone,ResourceRecordSetCount]" \
        --output table
      echo "Set route53_zone_id in infra/terraform/envs/$ENV.tfvars to the correct public zone ID (strip /hostedzone/ prefix)."
      exit 0
      ;;

    api-test)
      # POST a brief request and print response + timings.
      api_domain="$(awk -F'=' '/^api_domain/ {gsub(/[[:space:]\"]/, "", $2); print $2; exit}' "$ROOT_DIR/infra/terraform/envs/$ENV.tfvars")"
      if [ -z "$api_domain" ]; then
        api_domain="api.threadbrief.com"
      fi
      api_base="https://${api_domain}"
      source_url="${ARG:-https://www.youtube.com/watch?v=dQw4w9WgXcQ}"
      length="${LENGTH:-brief}"
      mode="${MODE:-insights}"
      output_language="${OUTPUT_LANGUAGE:-en}"
      payload=$(cat <<JSON
{
  "source_type": "youtube",
  "source": "${source_url}",
  "mode": "${mode}",
  "length": "${length}",
  "output_language": "${output_language}"
}
JSON
)
      curl -sS -w "\nHTTP %{http_code}\nTotal %{time_total}s\nConnect %{time_connect}s\nTLS %{time_appconnect}s\nTTFB %{time_starttransfer}s\n" \
        -X POST "${api_base}/v1/briefs" \
        -H "Content-Type: application/json" \
        --max-time 930 \
        --connect-timeout 10 \
        -d "$payload"
      exit 0
      ;;

    down|destroy)
      # Tear down infrastructure via terraform destroy
      echo "[$ENV] Terraform destroy..."
      tf_init_select_workspace "$ENV" "$ROOT_DIR/infra/terraform"
      AWS_REGION="${AWS_REGION:-ap-southeast-2}"
      vars_args=(-var-file="$ROOT_DIR/infra/terraform/envs/$ENV.tfvars")
      if [ -n "${ROUTE53_ZONE_ID:-}" ]; then
        vars_args+=(-var "route53_zone_id=$ROUTE53_ZONE_ID")
      fi

      if [ "$ENV" = "prod" ] || [ "$ENV" = "stage" ]; then
        # Keep Route53 zone, but remove it from state so destroy does not block.
        # Handle both old and count-based addresses.
        terraform -chdir="$ROOT_DIR/infra/terraform" state rm 'aws_route53_zone.this' >/dev/null 2>&1 || true
        terraform -chdir="$ROOT_DIR/infra/terraform" state rm 'aws_route53_zone.this[0]' >/dev/null 2>&1 || true
      fi

      # Some accounts block destroy if ECR repos contain images or have settings.
      # Targeted apply can break when resource addresses shift, so keep it prod-only.
      if [ "$ENV" = "prod" ]; then
        ecr_targets=()
        if aws ecr describe-repositories --region "$AWS_REGION" --repository-names "threadbrief-$ENV-api" >/dev/null 2>&1; then
          ecr_targets+=(-target=aws_ecr_repository.api)
        fi
        if aws ecr describe-repositories --region "$AWS_REGION" --repository-names "threadbrief-$ENV-web" >/dev/null 2>&1; then
          ecr_targets+=(-target=aws_ecr_repository.web)
        fi
        if [ "${#ecr_targets[@]}" -gt 0 ]; then
          terraform -chdir="$ROOT_DIR/infra/terraform" apply "${vars_args[@]}" "${ecr_targets[@]}" -auto-approve
        fi
      fi

      # Stage uses an imported ECS service-linked role sometimes; remove it from state
      # so destroy doesn't try to delete the AWS-managed role (often not allowed).
      if [ "$ENV" != "prod" ]; then
        terraform -chdir="$ROOT_DIR/infra/terraform" state rm aws_iam_service_linked_role.ecs >/dev/null 2>&1 || true
      fi

      log_path="$(tf_log_path "$ENV" "down" "$ROOT_DIR/infra/terraform")"
      terraform -chdir="$ROOT_DIR/infra/terraform" destroy "${vars_args[@]}" -auto-approve 2>&1 | tee "$log_path"
      echo "[$ENV] Terraform log: $log_path"
      exit 0
      ;;

    resync)
      # Manually import resources into state
      echo "[$ENV] Resyncing existing resources into state..."
      tf_resync_state "$ENV" "$ROOT_DIR/infra/terraform"
      exit 0
      ;;

    unlock)
      # If Terraform crashed mid-run, the state can be locked. This clears it.
      if [ -z "${ARG:-}" ]; then
        echo "Missing lock id for unlock."
        exit 1
      fi
      terraform -chdir="$ROOT_DIR/infra/terraform" force-unlock "$ARG"
      exit 0
      ;;

    plan)
      # Show what terraform WOULD change, without applying
      tf_init_select_workspace "$ENV" "$ROOT_DIR/infra/terraform"
      vars_args=(-var-file="envs/$ENV.tfvars")
      if [ -n "${ROUTE53_ZONE_ID:-}" ]; then
        vars_args+=(-var "route53_zone_id=$ROUTE53_ZONE_ID")
      fi
      if ! terraform -chdir="$ROOT_DIR/infra/terraform" plan "${vars_args[@]}"; then
        echo "[$ENV] Plan failed. If the state is locked, run: sh bin/tools.sh $ENV unlock <lock_id>" >&2
        exit 1
      fi
      exit 0
      ;;

    status)
      # Quick diagnostics: state file + lock file if present
      tf_dir="$ROOT_DIR/infra/terraform"
      lock_file="$tf_dir/terraform.tfstate.d/$ENV/.terraform.tfstate.lock.info"
      state_file="$tf_dir/terraform.tfstate.d/$ENV/terraform.tfstate"
      echo "[$ENV] Terraform status"
      if [ -f "$state_file" ]; then
        echo "State file: $state_file"
        stat -f "  modified: %Sm" -t "%Y-%m-%d %H:%M:%S" "$state_file"
      else
        echo "State file: missing"
      fi
      if [ -f "$lock_file" ]; then
        echo "Lock file: $lock_file"
        cat "$lock_file"
      else
        echo "Lock file: none"
      fi
      exit 0
      ;;

    tail)
      # Tail the latest terraform up/down log file
      tf_dir="$ROOT_DIR/infra/terraform"
      log_dir="$tf_dir/logs"
      if [ ! -d "$log_dir" ]; then
        echo "No log directory found at $log_dir."
        exit 1
      fi
      log_file="$(ls -t "$log_dir"/"$ENV"-*.log 2>/dev/null | head -n 1)"
      if [ -z "$log_file" ]; then
        echo "No logs found for $ENV in $log_dir."
        exit 1
      fi
      echo "Tailing $log_file"
      tail -f "$log_file"
      exit 0
      ;;

    logs)
      # CloudWatch logs tail (ECS task logs)
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
      # Debug ALB + listeners + target health
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
      # Deploy pipeline:
      #   1) Ensure secrets are restored/imported (so Terraform apply won't fail)
      #   2) Terraform apply (creates infra if missing)
      #   3) Get ECR repo URLs + ECS service names from Terraform outputs
      #   4) docker build + docker push API + WEB images
      #   5) force-new-deployment on ECS services
      echo "[$ENV] Deploying images to ECR and updating ECS services..."
      AWS_REGION="${AWS_REGION:-ap-southeast-2}"
      TAG="${TAG:-latest}"
      TF_DIR="$ROOT_DIR/infra/terraform"

      # If Docker isn't running, build/push can't work
      if ! docker info >/dev/null 2>&1; then
        echo "Docker daemon not running. Start Docker Desktop and retry." >&2
        exit 1
      fi

      # Auto-restore secrets that are scheduled for deletion so apply can recreate/attach them.
      # (AWS Secrets Manager lets you schedule deletion; restore cancels it.)
      for secret_name in \
        "threadbrief/$ENV/gemini_api_key" \
        "threadbrief/$ENV/ytdlp_cookies" \
        "threadbrief/$ENV/ytdlp_proxy"; do
        if aws secretsmanager describe-secret --secret-id "$secret_name" --query "DeletedDate" --output text >/dev/null 2>&1; then
          if [ "$(aws secretsmanager describe-secret --secret-id "$secret_name" --query "DeletedDate" --output text 2>/dev/null)" != "None" ]; then
            aws secretsmanager restore-secret --secret-id "$secret_name" >/dev/null
          fi
        fi
      done

      # Collect terraform var files:
      #   envs/<ENV>.tfvars is required
      #   envs/<ENV>.local.tfvars optional override (not committed, usually)
      VARS_ARGS=(-var-file="$TF_DIR/envs/$ENV.tfvars")
      if [ -f "$TF_DIR/envs/$ENV.local.tfvars" ]; then
        VARS_ARGS+=(-var-file="$TF_DIR/envs/$ENV.local.tfvars")
      fi
      if [ -n "${ROUTE53_ZONE_ID:-}" ]; then
        VARS_ARGS+=(-var "route53_zone_id=$ROUTE53_ZONE_ID")
      fi

      # Some values are provided as TF vars from local files (cookies/proxy)
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

      # Import any existing secrets into state so apply doesn't fail on duplicates.
      # This is the exact same concept as Route53 zones: "if it exists, import it first"
      for secret_name in \
        "threadbrief/$ENV/gemini_api_key:aws_secretsmanager_secret.gemini[0]" \
        "threadbrief/$ENV/ytdlp_cookies:aws_secretsmanager_secret.ytdlp_cookies[0]" \
        "threadbrief/$ENV/ytdlp_proxy:aws_secretsmanager_secret.ytdlp_proxy[0]"; do
        secret_id="${secret_name%%:*}"
        tf_addr="${secret_name##*:}"
        if aws secretsmanager describe-secret --secret-id "$secret_id" --query "ARN" --output text >/dev/null 2>&1; then
          secret_arn="$(aws secretsmanager describe-secret --secret-id "$secret_id" --query "ARN" --output text 2>/dev/null)"
          if [ -n "$secret_arn" ] && [ "$secret_arn" != "None" ]; then
            terraform -chdir="$TF_DIR" import "${VARS_ARGS[@]}" "$tf_addr" "$secret_arn" >/dev/null 2>&1 || true
          fi
        fi
      done

      # Optionally resync before apply (RESYNC=1)
      if [ "${RESYNC:-}" = "1" ]; then
        echo "[$ENV] Resyncing existing resources into state..."
        tf_resync_state "$ENV" "$TF_DIR"
      else
        tf_init_select_workspace "$ENV" "$TF_DIR"
      fi

      # Apply infra
      terraform -chdir="$TF_DIR" apply "${VARS_ARGS[@]}" -auto-approve

      # Pull outputs from terraform (source of truth for repo URLs + service names)
      api_repo="$(terraform -chdir="$TF_DIR" output -raw api_ecr_url)"
      web_repo="$(terraform -chdir="$TF_DIR" output -raw web_ecr_url)"
      cluster_name="$(terraform -chdir="$TF_DIR" output -raw ecs_cluster_name)"
      api_service="$(terraform -chdir="$TF_DIR" output -raw api_service_name)"
      web_service="$(terraform -chdir="$TF_DIR" output -raw web_service_name)"
      api_domain="$(terraform -chdir="$TF_DIR" output -raw api_domain)"

      # Login to ECR (auth token)
      aws ecr get-login-password --region "$AWS_REGION" \
        | docker login --username AWS --password-stdin "${api_repo%/*}"

      # Build + push API container
      echo "[BUILD] API image"
      docker build -t "$api_repo:$TAG" "$ROOT_DIR/services/api"
      docker push "$api_repo:$TAG"

      # Build + push WEB container (inject API base URL into Next.js build)
      echo "[BUILD] WEB image"
      docker build -t "$web_repo:$TAG" \
        --build-arg NEXT_PUBLIC_API_BASE_URL="https://${api_domain}" \
        --build-arg NEXT_PUBLIC_MAX_VIDEO_MINUTES="${MAX_VIDEO_MINUTES:-10}" \
        -f "$ROOT_DIR/services/web/Dockerfile.prod" \
        "$ROOT_DIR/services/web"
      docker push "$web_repo:$TAG"

      # Restart ECS services so they pull the new image tag
      echo "[DEPLOY] Updating ECS services"
      aws ecs update-service --cluster "$cluster_name" --service "$api_service" --force-new-deployment > /dev/null
      aws ecs update-service --cluster "$cluster_name" --service "$web_service" --force-new-deployment > /dev/null

      echo "[DONE] Deploy triggered for $ENV (tag=$TAG)"
      exit 0
      ;;

    *) echo "Unknown command for $ENV: $CMD"; help; exit 1 ;;
  esac
fi

# -----------------------------------------------------------------------------
# DEV commands (Docker compose local workflow)
# -----------------------------------------------------------------------------
case "$CMD" in
  up)
    echo "[DEV] Starting containers..."
    # If cookies/proxy exist locally, export them so containers can use them
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
