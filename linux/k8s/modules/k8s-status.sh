#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

load_env_files
require_kubectl

K="$(kubectl_bin)"
NS="$(ns_name)"

echo "=== Status Absenta (Namespace: $NS) ==="
echo ""
echo "--- Services (Akses lewat IP WireGuard Bapak) ---"
$K -n "$NS" get svc -o wide | grep -v "CLUSTER-IP" || $K -n "$NS" get svc -o wide

echo ""
echo "--- Deployments (Aplikasi) ---"
$K -n "$NS" get deployments -o wide

echo ""
echo "--- Pods (Kondisi saat ini) ---"
$K -n "$NS" get pods -o wide

echo ""
echo "Catatan: Jika port NodePort tidak muncul di 'ss -tulpn', silakan gunakan menu 'Fix Networking'."

