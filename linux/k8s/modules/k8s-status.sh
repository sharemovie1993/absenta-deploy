#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

load_env_files
require_kubectl

K="$(kubectl_bin)"
NS="$(ns_name)"

$K get ns "$NS" >/dev/null 2>&1 || { echo "Namespace not found: $NS"; exit 1; }
$K -n "$NS" get deploy,svc,pods -o wide

