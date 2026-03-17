#!/usr/bin/env bash
set -euo pipefail

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

run_status() { echo "--> Memeriksa status server..."; bash -vx "$DIR/modules/status.sh"; }
run_firewall_menu() { echo "--> Membuka menu firewall..."; bash -vx "$DIR/modules/firewall-menu.sh"; }
run_hardening() { echo "--> Menjalankan hardening basic..."; bash -vx "$DIR/modules/hardening-basic.sh"; }
run_wireguard_menu() { echo "--> Membuka menu WireGuard..."; bash -vx "$DIR/modules/wireguard-menu.sh"; }
run_postgres_menu() { echo "--> Membuka menu PostgreSQL..."; bash -vx "$DIR/modules/postgres-menu.sh"; }
run_redis_menu() { echo "--> Membuka menu Redis..."; bash -vx "$DIR/modules/redis-menu.sh"; }
run_ssh_menu() { echo "--> Membuka menu SSH..."; bash -vx "$DIR/modules/ssh-menu.sh"; }
run_network_menu() { echo "--> Membuka menu Network..."; bash -vx "$DIR/modules/network-menu.sh"; }
run_time_sync() { echo "--> Melakukan sinkronisasi waktu..."; bash -vx "$DIR/modules/time-sync.sh"; }
run_role_wizard() { echo "--> Membuka role wizard..."; bash -vx "$DIR/modules/role-wizard.sh"; }
run_monitoring_menu() { echo "--> Membuka menu monitoring..."; bash -vx "$DIR/modules/monitoring-menu.sh"; }
run_runbook_menu() { echo "--> Membuka menu runbook..."; bash -vx "$DIR/modules/runbook-menu.sh"; }
run_k8s_menu() {
  local k8s_script="$DIR/../k8s/absenta-k8s.sh"
  if [ -f "$k8s_script" ]; then
    echo "--> Berpindah ke Menu K8s..."
    cd "$(dirname "$k8s_script")" && exec bash -vx "$(basename "$k8s_script")"
  else
    echo "Kesalahan: Menu K8s tidak ditemukan di $k8s_script"
    sleep 2
  fi
}
run_old_menu() {
  local old_script="$DIR/../deploy_old/absenta_menu.sh"
  if [ -f "$old_script" ]; then
    echo "--> Berpindah ke Menu Lama (Legacy)..."
    cd "$(dirname "$old_script")" && exec bash -vx "$(basename "$old_script")"
  else
    echo "Kesalahan: Menu Lama tidak ditemukan di $old_script"
    sleep 2
  fi
}

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
  echo "13) Ke Menu K8S (k3s/deploy)"
  echo "14) Ke Menu Lama (Legacy / Deploy Old)"
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
    13) run_k8s_menu ;;
    14) run_old_menu ;;
    0) exit 0 ;;
    *) echo "Pilihan tidak dikenal" ;;
  esac
done
