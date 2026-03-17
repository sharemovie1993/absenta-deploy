#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/lib/common.sh"

ensure_tools() {
  need_cmd bash
  need_cmd awk
  need_cmd sed
  need_cmd grep
  need_cmd curl
}

ensure_tools

run_status() { bash "$DIR/modules/status.sh"; }
run_firewall_menu() { bash "$DIR/modules/firewall-menu.sh"; }
run_hardening() { bash "$DIR/modules/hardening-basic.sh"; }
run_wireguard_menu() { bash "$DIR/modules/wireguard-menu.sh"; }
run_postgres_menu() { bash "$DIR/modules/postgres-menu.sh"; }
run_redis_menu() { bash "$DIR/modules/redis-menu.sh"; }
run_ssh_menu() { bash "$DIR/modules/ssh-menu.sh"; }
run_network_menu() { bash "$DIR/modules/network-menu.sh"; }
run_time_sync() { bash "$DIR/modules/time-sync.sh"; }
run_role_wizard() { bash "$DIR/modules/role-wizard.sh"; }
run_monitoring_menu() { bash "$DIR/modules/monitoring-menu.sh"; }
run_runbook_menu() { bash "$DIR/modules/runbook-menu.sh"; }

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
