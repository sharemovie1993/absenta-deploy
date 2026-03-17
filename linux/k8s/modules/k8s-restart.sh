#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

load_env_files
require_kubectl

K="$(kubectl_bin)"
NS="$(ns_name)"

echo "--> Merestart semua layanan Absenta di namespace=$NS..."
$K rollout restart deployment -n "$NS"

echo "--> Menunggu restart selesai (rollout status)..."
# We can't easily wait for --all in a single rollout status command without a loop,
# but we can at least wait for the main API.
$K -n "$NS" rollout status deploy/backend-api --timeout=60s || true

echo "Done. Semua pod sedang dalam proses restart (rolling update)."
$K -n "$NS" get pods
