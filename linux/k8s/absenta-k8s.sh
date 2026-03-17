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

run_install_k3s() { echo "--> Memulai instalasi/update k3s..."; bash "$DIR/modules/k3s-install.sh"; }
run_build() { echo "--> Memulai build images (backend/frontend)..."; bash "$DIR/modules/k8s-build.sh"; }
run_deploy() { echo "--> Memulai deploy/update Absenta ke k3s..."; bash "$DIR/modules/k8s-deploy.sh"; }
run_status() { echo "--> Memeriksa status pods/svc..."; bash "$DIR/modules/k8s-status.sh"; }
run_logs() { echo "--> Menampilkan log backend-api..."; bash "$DIR/modules/k8s-logs.sh"; }
run_uninstall_app() { echo "--> Memulai uninstall Absenta (hapus namespace)..."; bash "$DIR/modules/k8s-uninstall-app.sh"; }
run_uninstall_k3s() { echo "--> Memulai uninstall k3s (hapus cluster)..."; bash "$DIR/modules/k3s-uninstall.sh"; }
run_runbook() { echo "--> Membuka menu runbook..."; bash "$DIR/modules/runbook.sh"; }
run_old_menu() {
  local old_script="$DIR/../deploy_old/absenta_menu.sh"
  if [ -f "$old_script" ]; then
    echo "--> Berpindah ke Menu Lama (Legacy)..."
    cd "$(dirname "$old_script")" && exec bash "$(basename "$old_script")"
  else
    echo "Kesalahan: Menu Lama tidak ditemukan di $old_script"
    sleep 2
  fi
}
run_toolbox_menu() {
  local toolbox_script="$DIR/../toolbox/absenta-toolbox.sh"
  if [ -f "$toolbox_script" ]; then
    echo "--> Berpindah ke Menu Toolbox..."
    cd "$(dirname "$toolbox_script")" && exec bash "$(basename "$toolbox_script")"
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
  echo "4) Status (pods/svc)"
  echo "5) Logs (backend-api)"
  echo "6) Runbook (baca panduan dari menu)"
  echo "7) Uninstall Absenta (hapus namespace)"
  echo "8) Uninstall k3s (hapus cluster di node ini)"
  echo "9) Ke Menu Toolbox (Infra/DB/Safe)"
  echo "10) Ke Menu Lama (Legacy / Deploy Old)"
  echo "0) Keluar"
  read -rp "Pilih: " opt
  case "${opt:-}" in
    1) run_install_k3s ;;
    2) run_build ;;
    3) run_deploy ;;
    4) run_status ;;
    5) run_logs ;;
    6) run_runbook ;;
    7) run_uninstall_app ;;
    8) run_uninstall_k3s ;;
    9) run_toolbox_menu ;;
    10) run_old_menu ;;
    0) exit 0 ;;
    *) echo "Pilihan tidak dikenal" ;;
  esac
done
