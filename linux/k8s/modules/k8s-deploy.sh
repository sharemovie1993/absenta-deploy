#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

need_cmd mktemp

load_env_files
require_kubectl

K="$(kubectl_bin)"
NS="$(ns_name)"

OUT="$(bash "$DIR/k8s-render.sh")"

echo "Applying manifests to namespace=$NS"
$K apply -R -f "$OUT"

echo "--> Menunggu pod menyala (Live Status)..."
# Jalankan status monitor di background selama rollout
(
  while true; do
    echo "--- [Status Pod @ $(date +%H:%M:%S)] ---"
    $K -n "$NS" get pods --no-headers | grep -v "Completed" | head -n 5
    sleep 3
  done
) &
MONITOR_PID=$!

# Tunggu rollout selesai
$K -n "$NS" rollout status deploy/backend-api --timeout=180s || {
  echo "Peringatan: Rollout timeout. Menampilkan log error terakhir:"
  $K -n "$NS" logs deploy/backend-api --tail=20
}

# Matikan monitor background
kill $MONITOR_PID 2>/dev/null || true

$K -n "$NS" get pods
$K -n "$NS" get svc
echo "Done"

