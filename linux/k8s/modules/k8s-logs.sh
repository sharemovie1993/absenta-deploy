#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

load_env_files
require_kubectl

K="$(kubectl_bin)"
NS="$(ns_name)"

pod="$($K -n "$NS" get pods -l app=backend-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [ -z "${pod:-}" ]; then
  echo "backend-api pod not found"
  exit 1
fi

$K -n "$NS" logs -f "$pod" --tail=200

