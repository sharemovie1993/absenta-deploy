#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$DIR/lib"

. "$LIB/common.sh"

ensure_tools() {
  echo "--> Memeriksa ketersediaan tool K8s..."
  need_cmd bash
  need_cmd awk
  need_cmd sed
  need_cmd grep
  need_cmd base64
  need_cmd uname
}

run_install_k3s() { echo "--> Memulai instalasi/update k3s..."; bash -vx "$DIR/modules/k3s-install.sh"; }
run_build() { echo "--> Memulai build images (backend/frontend)..."; bash -vx "$DIR/modules/k8s-build.sh"; }
run_deploy() { echo "--> Memulai deploy/update Absenta ke k3s..."; bash -vx "$DIR/modules/k8s-deploy.sh"; }
run_migrate() { echo "--> Menjalankan database migration & seed..."; bash -vx "$DIR/modules/k8s-migrate.sh"; }
run_status() { echo "--> Memeriksa status pods/svc..."; bash -vx "$DIR/modules/k8s-status.sh"; }
run_logs() { echo "--> Menampilkan log backend-api..."; bash -vx "$DIR/modules/k8s-logs.sh"; }
run_restart() { echo "--> Melakukan restart layanan (rollout)..."; bash -vx "$DIR/modules/k8s-restart.sh"; }
run_uninstall_app() { echo "--> Memulai uninstall Absenta (hapus namespace)..."; bash -vx "$DIR/modules/k8s-uninstall-app.sh"; }
run_uninstall_k3s() { echo "--> Memulai uninstall k3s (hapus cluster)..."; bash -vx "$DIR/modules/k3s-uninstall.sh"; }
run_runbook() { echo "--> Membuka menu runbook..."; bash -vx "$DIR/modules/runbook.sh"; }
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
run_toolbox_menu() {
  local toolbox_script="$DIR/../toolbox/absenta-toolbox.sh"
  if [ -f "$toolbox_script" ]; then
    echo "--> Berpindah ke Menu Toolbox..."
    cd "$(dirname "$toolbox_script")" && exec bash -vx "$(basename "$toolbox_script")"
  else
    echo "Kesalahan: Menu Toolbox tidak ditemukan di $toolbox_script"
    sleep 2
  fi
}

ensure_tools

if [ ! -t 0 ] || [ ! -t 1 ]; then
  run_deploy
  exit 0
fi

while true; do
  echo ""
  echo "=== ABSENTA K8S MENU (k3s single-node) ==="
  echo "1) Install/Update k3s"
  echo "2) Build Images (Backend & Frontend)"
  echo "3) Deploy/Update Absenta ke k3s (NodePort)"
  echo "4) Migration & Seed (Database setup)"
  echo "5) Status (pods/svc)"
  echo "6) Logs (backend-api)"
  echo "7) Restart (Rolling update semua pod)"
  echo "8) Runbook (baca panduan dari menu)"
  echo "9) Uninstall Absenta (hapus namespace)"
  echo "10) Uninstall k3s (hapus cluster di node ini)"
  echo "11) Ke Menu Toolbox (Infra/DB/Safe)"
  echo "12) Ke Menu Lama (Legacy / Deploy Old)"
  echo "0) Keluar"
  read -rp "Pilih: " opt
  case "${opt:-}" in
    1) run_install_k3s ;;
    2) run_build ;;
    3) run_deploy ;;
    4) run_migrate ;;
    5) run_status ;;
    6) run_logs ;;
    7) run_restart ;;
    8) run_runbook ;;
    9) run_uninstall_app ;;
    10) run_uninstall_k3s ;;
    11) run_toolbox_menu ;;
    12) run_old_menu ;;
    0) exit 0 ;;
    *) echo "Pilihan tidak dikenal" ;;
  esac
done
