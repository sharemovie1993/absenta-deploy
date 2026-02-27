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

add_server() {
  local UPN="$1"
  local HOST="$2"
  local PORT="$3"
  if [ -z "$UPN" ] || [ -z "$HOST" ] || [ -z "$PORT" ]; then
    echo "Usage: add <UPSTREAM_NAME> <HOST> <PORT>"
    return 1
  fi
  if ! grep -E "^[[:space:]]*upstream[[:space:]]+${UPN}[[:space:]]*\\{" -q "$NGINX_CONF"; then
    echo "Upstream '${UPN}' tidak ditemukan di $NGINX_CONF"
    return 1
  fi
  if awk -v u="$UPN" -v h="$HOST" -v p="$PORT" '
    /^\s*upstream[[:space:]]+[^{]+{/ {
      if (match($0, /upstream[[:space:]]+([^ \t{]+)/, m)) {
        upstream=m[1]; in_upstream=(upstream==u);
      }
      next
    }
    in_upstream && /}/ { in_upstream=0; next }
    in_upstream && $0 ~ ("server[[:space:]]+" h ":" p) { found=1 }
    END { exit found?0:1 }
  ' "$NGINX_CONF"; then
    echo "Server ${HOST}:${PORT} sudah ada di upstream ${UPN}."
    return 0
  fi
  backup_conf
  if check_tcp "$HOST" "$PORT"; then
    sed -E -i "/upstream[[:space:]]+${UPN}[[:space:]]*\\{/,/\\}/{/\\}/{i\\    server ${HOST}:${PORT};}" "$NGINX_CONF"
    echo "Menambahkan server ${HOST}:${PORT} (UP) ke upstream ${UPN}."
  else
    sed -E -i "/upstream[[:space:]]+${UPN}[[:space:]]*\\{/,/\\}/{/\\}/{i\\    server ${HOST}:${PORT} down;}" "$NGINX_CONF"
    echo "Menambahkan server ${HOST}:${PORT} (UNREACHABLE -> down) ke upstream ${UPN}."
  fi
  nginx -t && systemctl reload nginx
}

remove_server() {
  local UPN="$1"
  local HOST="$2"
  local PORT="$3"
  if [ -z "$UPN" ] || [ -z "$HOST" ] || [ -z "$PORT" ]; then
    echo "Usage: remove <UPSTREAM_NAME> <HOST> <PORT>"
    return 1
  fi
  if ! grep -E "^[[:space:]]*upstream[[:space:]]+${UPN}[[:space:]]*\\{" -q "$NGINX_CONF"; then
    echo "Upstream '${UPN}' tidak ditemukan di $NGINX_CONF"
    return 1
  fi
  backup_conf
  sed -E -i "/upstream[[:space:]]+${UPN}[[:space:]]*\\{/,/\\}/{/server[[:space:]]+${HOST}:${PORT}([[:space:]]+down)?[[:space:]]*;/d}" "$NGINX_CONF"
  nginx -t && systemctl reload nginx
  echo "Menghapus server ${HOST}:${PORT} dari upstream ${UPN}."
}

auto_remove_down_or_unreachable() {
  local TARGET_UPSTREAM="$1"
  backup_conf
  local changed=0
  while IFS='|' read -r UPSTREAM HOST PORT FLAG; do
    if [ -n "$TARGET_UPSTREAM" ] && [ "$UPSTREAM" != "$TARGET_UPSTREAM" ]; then
      continue
    fi
    local should_remove=0
    if [ "$FLAG" = "down" ]; then
      should_remove=1
    else
      if ! check_tcp "$HOST" "$PORT"; then
        should_remove=1
      fi
    fi
    if [ "$should_remove" -eq 1 ]; then
      sed -E -i "/upstream[[:space:]]+${UPSTREAM}[[:space:]]*\\{/,/\\}/{/server[[:space:]]+${HOST}:${PORT}([[:space:]]+down)?[[:space:]]*;/d}" "$NGINX_CONF"
      echo "Menghapus ${UPSTREAM} ${HOST}:${PORT} (down/unreachable)."
      changed=1
    fi
  done < <(awk '
    /^\s*upstream[[:space:]]+[^{]+{/ {
      if (match($0, /upstream[[:space:]]+([^ \t{]+)/, m)) {
        upstream=m[1]; in_upstream=1;
      }
      next
    }
    in_upstream && /}/ { in_upstream=0; next }
    in_upstream && /server[[:space:]]+[0-9A-Za-z\.\-:]+/ {
      flag="";
      if ($0 ~ /down[[:space:]]*;/) flag="down";
      if (match($0, /server[[:space:]]+([0-9A-Za-z\.\-]+):([0-9]+)/, s)) {
        print upstream "|" s[1] "|" s[2] "|" flag
      }
    }
  ' "$NGINX_CONF")
  if [ "$changed" -eq 1 ]; then
    nginx -t && systemctl reload nginx
  else
    echo "Tidak ada server down/unreachable untuk dihapus."
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
    echo "5) Tambah server ke upstream"
    echo "6) Hapus server dari upstream"
    echo "7) Auto-remove server DOWN/tidak dapat diakses"
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
      5)
        read -p "Nama upstream: " UPN
        read -p "Host upstream (contoh 10.50.0.2): " HOST
        read -p "Port upstream (contoh 3000 atau 8080): " PORT
        add_server "$UPN" "$HOST" "$PORT"
        read -p "Tekan Enter untuk lanjut..."
        ;;
      6)
        read -p "Nama upstream: " UPN
        read -p "Host upstream (contoh 10.50.0.2): " HOST
        read -p "Port upstream (contoh 3000 atau 8080): " PORT
        remove_server "$UPN" "$HOST" "$PORT"
        read -p "Tekan Enter untuk lanjut..."
        ;;
      7)
        read -p "Nama upstream (kosongkan untuk semua): " UPN
        auto_remove_down_or_unreachable "$UPN"
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
elif [ "$1" = "add" ]; then
  add_server "$2" "$3" "$4"
elif [ "$1" = "remove" ]; then
  remove_server "$2" "$3" "$4"
elif [ "$1" = "auto-remove" ]; then
  auto_remove_down_or_unreachable "$2"
else
  interactive_menu
fi
