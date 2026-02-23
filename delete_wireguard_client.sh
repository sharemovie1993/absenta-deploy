#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

WG_DIR="/etc/wireguard"
mkdir -p "$WG_DIR"

read -p "Nama interface WireGuard (default wg0): " WG_IFACE
WG_IFACE=${WG_IFACE:-wg0}

WG_CONF="$WG_DIR/$WG_IFACE.conf"

if [ ! -f "$WG_CONF" ]; then
  echo "Config $WG_CONF tidak ditemukan. Pastikan server WireGuard sudah dikonfigurasi."
  exit 1
fi

echo "Daftar peer saat ini:"
wg show "$WG_IFACE" 2>/dev/null || echo "(wg tidak menampilkan peer, lanjut manual)"

read -p "Public key client yang akan dihapus: " CLIENT_PUBLIC_KEY

if [ -z "$CLIENT_PUBLIC_KEY" ]; then
  echo "Public key wajib diisi."
  exit 1
fi

BACKUP_FILE="${WG_CONF}.bak.$(date +%Y%m%d%H%M%S)"
cp "$WG_CONF" "$BACKUP_FILE"
echo "Backup konfigurasi dibuat di: $BACKUP_FILE"

TMP_CONF="${WG_CONF}.tmp"

awk -v key="$CLIENT_PUBLIC_KEY" '
BEGIN { RS=""; ORS="\n\n" }
{
  if ($0 ~ /\[Peer\]/ && $0 ~ "PublicKey = " key) {
    next
  }
  print
}
' "$WG_CONF" > "$TMP_CONF"

mv "$TMP_CONF" "$WG_CONF"

if command -v wg >/dev/null 2>&1; then
  if wg show "$WG_IFACE" 2>/dev/null | grep -q "$CLIENT_PUBLIC_KEY"; then
    wg set "$WG_IFACE" peer "$CLIENT_PUBLIC_KEY" remove || true
  fi
fi

systemctl restart "wg-quick@$WG_IFACE" || true

echo "Peer dengan public key $CLIENT_PUBLIC_KEY telah dihapus (config dan runtime)."
echo "Status WireGuard saat ini:"
wg show "$WG_IFACE" 2>/dev/null || echo "(wg tidak dapat menampilkan status)"

