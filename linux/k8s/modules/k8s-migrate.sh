#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

load_env_files
require_kubectl

K="$(kubectl_bin)"
NS="$(ns_name)"
IMAGE="$(backend_image)"

echo "=== Prisma Migration & Seed (K8s) ==="

# Kita jalankan temporary pod untuk migrate
echo "--> Menjalankan migration job..."
$K -n "$NS" run prisma-migrate-tmp \
  --image="$IMAGE" \
  --restart=Never \
  --rm -i --tty \
  --env-from=secret/absenta-secrets \
  --env-from=configmap/absenta-config \
  --command -- sh -c "npx prisma migrate deploy"

echo "--> Menjalankan database seed..."
$K -n "$NS" run prisma-seed-tmp \
  --image="$IMAGE" \
  --restart=Never \
  --rm -i --tty \
  --env-from=secret/absenta-secrets \
  --env-from=configmap/absenta-config \
  --command -- sh -c "npm run seed"

echo "=== Done ==="
