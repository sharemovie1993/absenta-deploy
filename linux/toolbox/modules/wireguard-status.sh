#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

IFACE="$(wg_iface)"
CFG="$(wg_dir)/${IFACE}.conf"

echo "=== WireGuard Status ==="
echo "Interface: ${IFACE}"
echo "Config: ${CFG}"
echo ""

if is_cmd systemctl; then
  as_root systemctl status "wg-quick@${IFACE}" --no-pager || true
  echo ""
fi

if is_cmd wg; then
  as_root wg show || true
else
  echo "wg command not found"
fi

