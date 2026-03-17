#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

echo "=== Node Exporter Status ==="
if is_cmd systemctl; then
  as_root systemctl status node_exporter --no-pager || true
fi
echo ""
if is_cmd ss; then
  ss -ltnp | grep -E ':9100' || true
fi

