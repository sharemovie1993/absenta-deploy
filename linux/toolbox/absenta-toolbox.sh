#!/usr/bin/env bash
set -euo pipefail
# Enable xtrace for better visibility if needed, but here we'll ensure sub-shells are also visible
# To make all sub-shells not silent, we can use bash -x or add set -x to them.
# For now, we will add more explicit logging and ensure commands are not hidden.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"

ensure_tools() {
  echo "--> Memeriksa ketersediaan tool sistem..."
  need_cmd bash
  need_cmd awk
  need_cmd sed
  need_cmd grep
  need_cmd curl
}

ensure_tools

run_status() { echo "--> Memeriksa status server..."; bash -x "$DIR/modules/status.sh"; }
run_firewall_menu() { echo "--> Membuka menu firewall..."; bash -x "$DIR/modules/firewall-menu.sh"; }
run_hardening() { echo "--> Menjalankan hardening basic..."; bash -x "$DIR/modules/hardening-basic.sh"; }
run_wireguard_menu() { echo "--> Membuka menu WireGuard..."; bash -x "$DIR/modules/wireguard-menu.sh"; }
run_postgres_menu() { echo "--> Membuka menu PostgreSQL..."; bash -x "$DIR/modules/postgres-menu.sh"; }
run_redis_menu() { echo "--> Membuka menu Redis..."; bash -x "$DIR/modules/redis-menu.sh"; }
run_ssh_menu() { echo "--> Membuka menu SSH..."; bash -x "$DIR/modules/ssh-menu.sh"; }
run_network_menu() { echo "--> Membuka menu Network..."; bash -x "$DIR/modules/network-menu.sh"; }
run_time_sync() { echo "--> Melakukan sinkronisasi waktu..."; bash -x "$DIR/modules/time-sync.sh"; }
run_role_wizard() { echo "--> Membuka role wizard..."; bash -x "$DIR/modules/role-wizard.sh"; }
run_monitoring_menu() { echo "--> Membuka menu monitoring..."; bash -x "$DIR/modules/monitoring-menu.sh"; }
run_runbook_menu() { echo "--> Membuka menu runbook..."; bash -x "$DIR/modules/runbook-menu.sh"; }

if [ ! -t 0 ] || [ ! -t 1 ]; then
  run_status
  exit 0
fi

while true; do
  echo ""
  echo "=== ABSENTA TOOLBOX (Infra Ops) ==="
  echo "1) Status server (CPU/RAM/Disk/Port/WireGuard/Docker)"
  echo "2) Firewall (UFW) menu"
  echo "3) Hardening basic (aman, konservatif)"
  echo "4) WireGuard menu (install/init/add-client/status)"
  echo "5) PostgreSQL menu (install/config/db-user/status)"
  echo "6) Redis menu (install/config/status)"
  echo "7) SSH menu (user/key/hardening/status)"
  echo "8) Network menu (netplan show/apply safe)"
  echo "9) Time sync (chrony)"
  echo "10) Role wizard (reverse-proxy / backend / postgres / redis)"
  echo "11) Monitoring menu (node exporter / health checks)"
  echo "12) Runbook (baca panduan dari menu)"
  echo "0) Keluar"
  read -rp "Pilih: " opt
  case "${opt:-}" in
    1) run_status ;;
    2) run_firewall_menu ;;
    3) run_hardening ;;
    4) run_wireguard_menu ;;
    5) run_postgres_menu ;;
    6) run_redis_menu ;;
    7) run_ssh_menu ;;
    8) run_network_menu ;;
    9) run_time_sync ;;
    10) run_role_wizard ;;
    11) run_monitoring_menu ;;
    12) run_runbook_menu ;;
    0) exit 0 ;;
    *) echo "Pilihan tidak dikenal" ;;
  esac
done
