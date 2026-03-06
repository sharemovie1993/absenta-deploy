#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

detect_fw() {
  if command -v ufw >/dev/null 2>&1; then
    echo "ufw"
    return
  fi
  if command -v firewall-cmd >/dev/null 2>&1; then
    echo "firewalld"
    return
  fi
  if command -v iptables >/dev/null 2>&1; then
    echo "iptables"
    return
  fi
  echo "none"
}

reload_fw() {
  case "$FW" in
    ufw)
      ufw reload || true
      ;;
    firewalld)
      firewall-cmd --reload || true
      ;;
    iptables)
      if command -v netfilter-persistent >/dev/null 2>&1; then
        netfilter-persistent save || true
      fi
      ;;
  esac
}

add_port() {
  read -p "Port: " PORT
  [ -z "$PORT" ] && { echo "Port wajib."; return; }
  read -p "Protocol (tcp/udp, default tcp): " PROTO
  PROTO=${PROTO:-tcp}
  case "$FW" in
    ufw)
      ufw allow "${PORT}/${PROTO}" || true
      ;;
    firewalld)
      firewall-cmd --permanent --add-port="${PORT}/${PROTO}" || true
      ;;
    iptables)
      iptables -C INPUT -p "$PROTO" --dport "$PORT" -j ACCEPT 2>/dev/null || iptables -I INPUT -p "$PROTO" --dport "$PORT" -j ACCEPT || true
      ;;
  esac
  reload_fw
}

del_port() {
  read -p "Port: " PORT
  [ -z "$PORT" ] && { echo "Port wajib."; return; }
  read -p "Protocol (tcp/udp, default tcp): " PROTO
  PROTO=${PROTO:-tcp}
  case "$FW" in
    ufw)
      ufw delete allow "${PORT}/${PROTO}" || true
      ;;
    firewalld)
      firewall-cmd --permanent --remove-port="${PORT}/${PROTO}" || true
      ;;
    iptables)
      iptables -D INPUT -p "$PROTO" --dport "$PORT" -j ACCEPT 2>/dev/null || true
      ;;
  esac
  reload_fw
}

add_service() {
  read -p "Nama service (contoh: nginx, http, https, cockpit): " SVC
  [ -z "$SVC" ] && { echo "Service wajib."; return; }
  case "$FW" in
    ufw)
      ufw allow "$SVC" || true
      ;;
    firewalld)
      firewall-cmd --permanent --add-service="$SVC" || true
      ;;
    iptables)
      echo "iptables tidak memiliki konsep 'service'. Gunakan tambah port."
      ;;
  esac
  reload_fw
}

del_service() {
  read -p "Nama service (contoh: http, https, cockpit): " SVC
  [ -z "$SVC" ] && { echo "Service wajib."; return; }
  case "$FW" in
    ufw)
      ufw delete allow "$SVC" || true
      ;;
    firewalld)
      firewall-cmd --permanent --remove-service="$SVC" || true
      ;;
    iptables)
      echo "iptables tidak memiliki konsep 'service'. Gunakan hapus port."
      ;;
  esac
  reload_fw
}

list_rules() {
  case "$FW" in
    ufw)
      ufw status numbered || true
      ;;
    firewalld)
      firewall-cmd --list-all || true
      ;;
    iptables)
      iptables -S | sed -n '1,200p' || true
      ;;
  esac
}

FW="$(detect_fw)"
if [ "$FW" = "none" ]; then
  echo "Tidak menemukan tool firewall (ufw/firewalld/iptables)."
  exit 0
fi

while true; do
  clear
  echo "=== Kelola Firewall (${FW}) ==="
  echo "1. Tambah aturan (port)"
  echo "2. Hapus aturan (port)"
  echo "3. Tambah service (ufw/firewalld)"
  echo "4. Hapus service (ufw/firewalld)"
  echo "5. Lihat aturan"
  echo "6. Reload firewall"
  echo "0. Kembali"
  read -p "Pilih: " ch
  case "$ch" in
    1) add_port; read -p "Enter untuk lanjut...";;
    2) del_port; read -p "Enter untuk lanjut...";;
    3) add_service; read -p "Enter untuk lanjut...";;
    4) del_service; read -p "Enter untuk lanjut...";;
    5) list_rules; read -p "Enter untuk lanjut...";;
    6) reload_fw; read -p "Enter untuk lanjut...";;
    0) break;;
    *) echo "Pilihan tidak dikenal"; read -p "Enter untuk lanjut...";;
  esac
done

