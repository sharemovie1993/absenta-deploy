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

list_down() {
  echo "=== Daftar server upstream yang sedang DOWN ==="
  awk '
    /^\s*upstream[[:space:]]+[^{]+{/ {
      if (match($0, /upstream[[:space:]]+([^ \t{]+)/, m)) {
        upstream=m[1]; in_upstream=1;
      }
      next
    }
    in_upstream && /}/ { in_upstream=0; upstream=""; next }
    in_upstream && /server[[:space:]]+[0-9A-Za-z\.\-:]+/ {
      if ($0 ~ /down[[:space:]]*;/) {
        gsub(/^[ \t]+|[ \t]+$/, "", $0);
        print upstream " | " $0
        found=1
      }
    }
    END {
      if (!found) {
        print "Tidak ada server yang ditandai DOWN di konfigurasi."
      }
    }
  ' "$NGINX_CONF"
}

check_tcp() {
  local HOST="$1"
  local PORT="$2"
  if command -v nc >/dev/null 2>&1; then
    nc -z -w 2 "$HOST" "$PORT"
  else
    (echo >"/dev/tcp/$HOST/$PORT") >/dev/null 2>&1
  fi
}

auto_mark_down() {
  local TARGET_UPSTREAM="$1"
  backup_conf
  local changed=0
  while IFS='|' read -r UPSTREAM HOST PORT; do
    if [ -n "$TARGET_UPSTREAM" ] && [ "$UPSTREAM" != "$TARGET_UPSTREAM" ]; then
      continue
    fi
    if ! check_tcp "$HOST" "$PORT"; then
      sed -E -i "s/(server[[:space:]]+${HOST}:${PORT}[^;]*);/\1 down;/" "$NGINX_CONF"
      echo "Menandai ${UPSTREAM} ${HOST}:${PORT} sebagai down (deteksi otomatis)."
      changed=1
    fi
  done < <(awk '
    /^\s*upstream[[:space:]]+[^{]+{/ {
      if (match($0, /upstream[[:space:]]+([^ \t{]+)/, m)) {
        upstream=m[1]; in_upstream=1;
      }
      next
    }
    in_upstream && /}/ { in_upstream=0; upstream=""; next }
    in_upstream && /server[[:space:]]+[0-9A-Za-z\.\-:]+/ {
      if ($0 !~ /down[[:space:]]*;/) {
        if (match($0, /server[[:space:]]+([0-9A-Za-z\.\-]+):([0-9]+)/, s)) {
          print upstream "|" s[1] "|" s[2]
        }
      }
    }
  ' "$NGINX_CONF")
  if [ "$changed" -eq 1 ]; then
    nginx -t && systemctl reload nginx
  else
    echo "Tidak ada server yang terdeteksi down."
  fi
}

interactive_menu() {
  while true; do
    clear
    echo "=== Manage Nginx Upstream (Mark down/up) ==="
    echo "1) Mark DOWN upstream server"
    echo "2) Mark UP upstream server"
    echo "3) Lihat server yang sedang DOWN"
    echo "4) Auto-detect & Mark DOWN (semua/berdasar upstream)"
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
      3)
        list_down
        read -p "Tekan Enter untuk lanjut..."
        ;;
      4)
        read -p "Nama upstream (kosongkan untuk semua): " UPN
        auto_mark_down "$UPN"
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
elif [ "$1" = "list-down" ] || [ "$1" = "list" ]; then
  list_down
elif [ "$1" = "auto" ] || [ "$1" = "auto-mark-down" ]; then
  auto_mark_down "$2"
else
  interactive_menu
fi
