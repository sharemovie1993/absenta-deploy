#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

run_install() { bash "$DIR/redis-install.sh"; }
run_status() { bash "$DIR/redis-status.sh"; }
run_config_wg() { bash "$DIR/redis-config-wireguard.sh"; }

while true; do
  echo ""
  echo "=== Redis Menu ==="
  echo "1) Install Redis"
  echo "2) Status (systemctl + redis-cli ping)"
  echo "3) Configure bind + requirepass for WireGuard"
  echo "0) Back"
  read -rp "Pilih: " opt
  case "${opt:-}" in
    1) run_install ;;
    2) run_status ;;
    3) run_config_wg ;;
    0) exit 0 ;;
    *) echo "Pilihan tidak dikenal" ;;
  esac
done

