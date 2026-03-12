#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY="$DIR/deploy-multinode.sh"

is_cmd() { command -v "$1" >/dev/null 2>&1; }

DOCKER_BIN="docker"
if ! docker info >/dev/null 2>&1; then
  if is_cmd sudo && sudo -n true 2>/dev/null; then
    DOCKER_BIN="sudo docker"
  fi
fi

single_compose="$DIR/docker-compose.linux.single.yml"
multi_compose="$DIR/docker-compose.linux.multi.yml"

show_status() {
  local compose="$1"
  $DOCKER_BIN compose -f "$compose" ps || true
  $DOCKER_BIN ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" || true
}

tail_logs() {
  local name="$1"
  $DOCKER_BIN logs --tail 200 -f "$name"
}

while true; do
  echo ""
  echo "=== ABSENTA MENU (Linux) ==="
  echo "1) Deploy/Update SINGLE (1 mesin: nginx+postgres+redis+api+workers)"
  echo "2) Deploy/Update MULTI (DB+Redis external, api+workers internal)"
  echo "3) Status SINGLE"
  echo "4) Status MULTI"
  echo "5) Logs API (absenta-backend-api)"
  echo "6) Restart SINGLE stack"
  echo "7) Restart MULTI stack"
  echo "8) Stop SINGLE stack"
  echo "9) Stop MULTI stack"
  echo "10) Cleanup disk docker (prune)"
  echo "11) Reset saved config (hapus /etc/absenta/*.env)"
  echo "0) Keluar"
  read -rp "Pilih: " opt

  case "${opt:-}" in
    1)
      MODE=single bash "$DEPLOY"
      ;;
    2)
      MODE=multi bash "$DEPLOY"
      ;;
    3)
      show_status "$single_compose"
      ;;
    4)
      show_status "$multi_compose"
      ;;
    5)
      tail_logs "absenta-backend-api"
      ;;
    6)
      $DOCKER_BIN compose -f "$single_compose" restart
      ;;
    7)
      $DOCKER_BIN compose -f "$multi_compose" restart
      ;;
    8)
      $DOCKER_BIN compose -f "$single_compose" down || true
      ;;
    9)
      $DOCKER_BIN compose -f "$multi_compose" down || true
      ;;
    10)
      $DOCKER_BIN system prune -af --volumes
      $DOCKER_BIN builder prune -af
      ;;
    11)
      if is_cmd sudo; then
        sudo rm -f /etc/absenta/single.env /etc/absenta/multi.env || true
      else
        rm -f /etc/absenta/single.env /etc/absenta/multi.env || true
      fi
      echo "Config reset OK"
      ;;
    0)
      exit 0
      ;;
    *)
      echo "Pilihan tidak dikenal"
      ;;
  esac
done

