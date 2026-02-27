#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

NGINX_CONF="${NGINX_CONF:-/etc/nginx/sites-available/absenta.conf}"

if [ ! -f "$NGINX_CONF" ]; then
  echo "File konfigurasi Nginx $NGINX_CONF tidak ditemukan."
  exit 1
fi

backup_conf() {
  TS="$(date +%Y%m%d%H%M%S)"
  cp "$NGINX_CONF" "${NGINX_CONF}.bak_${TS}" || true
  echo "Backup dibuat: ${NGINX_CONF}.bak_${TS}"
}

mark_down() {
  local HOST="$1"
  local PORT="$2"
  if [ -z "$HOST" ] || [ -z "$PORT" ]; then
    echo "Usage: mark_down <HOST> <PORT>"
    return 1
  fi
  backup_conf
  sed -E -i "s/(server[[:space:]]+${HOST}:${PORT}[^;]*);/\1 down;/" "$NGINX_CONF"
  nginx -t && systemctl reload nginx
  echo "Menandai upstream ${HOST}:${PORT} sebagai down."
}

mark_up() {
  local HOST="$1"
  local PORT="$2"
  if [ -z "$HOST" ] || [ -z "$PORT" ]; then
    echo "Usage: mark_up <HOST> <PORT>"
    return 1
  fi
  backup_conf
  sed -E -i "s/(server[[:space:]]+${HOST}:${PORT}[^;]*)[[:space:]]+down;/\1;/" "$NGINX_CONF"
  nginx -t && systemctl reload nginx
  echo "Mengembalikan upstream ${HOST}:${PORT} ke status up."
}

interactive_menu() {
  while true; do
    clear
    echo "=== Manage Nginx Upstream (Mark down/up) ==="
    echo "1) Mark DOWN upstream server"
    echo "2) Mark UP upstream server"
    echo "0) Kembali"
    read -p "Pilih: " CH
    case "$CH" in
      1)
        read -p "Host upstream (contoh 10.50.0.2): " HOST
        read -p "Port upstream (contoh 3000 atau 8080): " PORT
        mark_down "$HOST" "$PORT"
        read -p "Tekan Enter untuk lanjut..."
        ;;
      2)
        read -p "Host upstream (contoh 10.50.0.2): " HOST
        read -p "Port upstream (contoh 3000 atau 8080): " PORT
        mark_up "$HOST" "$PORT"
        read -p "Tekan Enter untuk lanjut..."
        ;;
      0)
        break
        ;;
      *)
        echo "Pilihan tidak dikenal"
        read -p "Tekan Enter untuk lanjut..."
        ;;
    esac
  done
}

if [ "$1" = "down" ]; then
  mark_down "$2" "$3"
elif [ "$1" = "up" ]; then
  mark_up "$2" "$3"
else
  interactive_menu
fi

