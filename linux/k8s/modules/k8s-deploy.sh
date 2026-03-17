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
$K apply -f "$OUT"

echo "Waiting for pods..."
$K -n "$NS" rollout status deploy/backend-api --timeout=180s || true
$K -n "$NS" get pods -o wide || true
$K -n "$NS" get svc || true

echo "Done"

