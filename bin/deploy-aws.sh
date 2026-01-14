#!/bin/bash
# Build + push images to ECR and force ECS service redeploys.

set -euo pipefail

ENV="${1:-}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -z "$ENV" ]; then
  echo "Usage: bin/deploy-aws.sh <stage|prod>"
  exit 1
fi

if [ "$ENV" != "stage" ] && [ "$ENV" != "prod" ]; then
  echo "Unknown env: $ENV (expected stage or prod)"
  exit 1
fi

AWS_REGION="${AWS_REGION:-ap-southeast-2}"
TAG="${TAG:-latest}"

TF_DIR="$ROOT_DIR/infra/terraform"
VARS_FILE="$TF_DIR/envs/$ENV.tfvars"

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
