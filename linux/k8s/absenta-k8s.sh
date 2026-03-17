#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$DIR/lib"

. "$LIB/common.sh"

ensure_tools() {
  need_cmd bash
  need_cmd awk
  need_cmd sed
  need_cmd grep
  need_cmd base64
  need_cmd uname
}

run_install_k3s() { bash "$DIR/modules/k3s-install.sh"; }
run_deploy() { bash "$DIR/modules/k8s-deploy.sh"; }
run_status() { bash "$DIR/modules/k8s-status.sh"; }
run_logs() { bash "$DIR/modules/k8s-logs.sh"; }
run_uninstall_app() { bash "$DIR/modules/k8s-uninstall-app.sh"; }
run_uninstall_k3s() { bash "$DIR/modules/k3s-uninstall.sh"; }
run_runbook() { bash "$DIR/modules/runbook.sh"; }

ensure_tools

if [ ! -t 0 ] || [ ! -t 1 ]; then
  run_deploy
  exit 0
fi

while true; do
  echo ""
  echo "=== ABSENTA K8S MENU (k3s single-node) ==="
  echo "1) Install/Update k3s"
  echo "2) Deploy/Update Absenta ke k3s (NodePort)"
  echo "3) Status (pods/svc)"
  echo "4) Logs (backend-api)"
  echo "5) Runbook (baca panduan dari menu)"
  echo "6) Uninstall Absenta (hapus namespace)"
  echo "7) Uninstall k3s (hapus cluster di node ini)"
  echo "0) Keluar"
  read -rp "Pilih: " opt
  case "${opt:-}" in
    1) run_install_k3s ;;
    2) run_deploy ;;
    3) run_status ;;
    4) run_logs ;;
    5) run_runbook ;;
    6) run_uninstall_app ;;
    7) run_uninstall_k3s ;;
    0) exit 0 ;;
    *) echo "Pilihan tidak dikenal" ;;
  esac
done
