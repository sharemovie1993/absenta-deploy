#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

run_show() { bash "$DIR/network-show.sh"; }
run_netplan_try() { bash "$DIR/network-netplan-try.sh"; }

while true; do
  echo ""
  echo "=== Network Menu (Ubuntu Netplan) ==="
  echo "1) Show network status (ip/route/dns)"
  echo "2) Netplan try (generate & apply with auto-rollback)"
  echo "0) Back"
  read -rp "Pilih: " opt
  case "${opt:-}" in
    1) run_show ;;
    2) run_netplan_try ;;
    0) exit 0 ;;
    *) echo "Pilihan tidak dikenal" ;;
  esac
done

