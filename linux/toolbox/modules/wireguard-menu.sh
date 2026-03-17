#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

run_install() { bash "$DIR/wireguard-install.sh"; }
run_init() { bash "$DIR/wireguard-init-server.sh"; }
run_add_client() { bash "$DIR/wireguard-add-client.sh"; }
run_status() { bash "$DIR/wireguard-status.sh"; }

while true; do
  echo ""
  echo "=== WireGuard Menu ==="
  echo "1) Install WireGuard"
  echo "2) Init server (generate wg0.conf)"
  echo "3) Add client (generate client config)"
  echo "4) Status (wg show / systemctl)"
  echo "0) Back"
  read -rp "Pilih: " opt
  case "${opt:-}" in
    1) run_install ;;
    2) run_init ;;
    3) run_add_client ;;
    4) run_status ;;
    0) exit 0 ;;
    *) echo "Pilihan tidak dikenal" ;;
  esac
done
