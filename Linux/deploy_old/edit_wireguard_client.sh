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

if command -v wg >/dev/null 2>&1; then
  echo "Daftar peer saat ini:"
  wg show "$WG_IFACE" 2>/dev/null || echo "(wg tidak menampilkan peer, lanjut manual)"
  echo ""
fi

read -p "Public key client yang akan diedit: " CLIENT_PUBLIC_KEY

if [ -z "$CLIENT_PUBLIC_KEY" ]; then
  echo "Public key wajib diisi."
  exit 1
fi

PEER_BLOCK=$(awk -v key="$CLIENT_PUBLIC_KEY" 'BEGIN { RS=""; ORS="\n\n" } $0 ~ /\[Peer\]/ && $0 ~ "PublicKey = " key { print }' "$WG_CONF")

if [ -z "$PEER_BLOCK" ]; then
  echo "Peer dengan public key tersebut tidak ditemukan di $WG_CONF."
  exit 1
fi

CURRENT_ALLOWED=$(printf "%s\n" "$PEER_BLOCK" | grep -m1 '^AllowedIPs' | awk -F'= ' '{print $2}' || true)
CURRENT_PKA=$(printf "%s\n" "$PEER_BLOCK" | grep -m1 '^PersistentKeepalive' | awk -F'= ' '{print $2}' || true)

if [ -z "$CURRENT_ALLOWED" ]; then
  CURRENT_ALLOWED="(belum diset)"
fi

echo "Nilai saat ini:"
echo "AllowedIPs           : $CURRENT_ALLOWED"
if [ -n "$CURRENT_PKA" ]; then
  echo "PersistentKeepalive  : $CURRENT_PKA"
else
  echo "PersistentKeepalive  : (belum diset)"
fi
echo ""

read -p "AllowedIPs baru (kosong = tetap: $CURRENT_ALLOWED): " NEW_ALLOWED_INPUT
if [ -n "$NEW_ALLOWED_INPUT" ]; then
  NEW_ALLOWED="$NEW_ALLOWED_INPUT"
else
  if [ "$CURRENT_ALLOWED" = "(belum diset)" ]; then
    echo "AllowedIPs tidak boleh kosong."
    exit 1
  fi
  NEW_ALLOWED="$CURRENT_ALLOWED"
fi

read -p "Persistent keepalive baru (detik, kosong = tidak diubah): " NEW_PKA_INPUT

UPDATE_PKA=0
NEW_PKA=""
if [ -n "$NEW_PKA_INPUT" ]; then
  UPDATE_PKA=1
  NEW_PKA="$NEW_PKA_INPUT"
fi

BACKUP_FILE="${WG_CONF}.bak.$(date +%Y%m%d%H%M%S)"
cp "$WG_CONF" "$BACKUP_FILE"
echo "Backup konfigurasi dibuat di: $BACKUP_FILE"

TMP_CONF="${WG_CONF}.tmp"

awk -v key="$CLIENT_PUBLIC_KEY" -v newAllowed="$NEW_ALLOWED" -v updatePka="$UPDATE_PKA" -v newPka="$NEW_PKA" '
BEGIN { RS=""; ORS="\n\n" }
{
  if ($0 ~ /\[Peer\]/ && $0 ~ "PublicKey = " key) {
    sub(/AllowedIPs = .*/, "AllowedIPs = " newAllowed, $0)
    if (updatePka == 1) {
      if ($0 ~ /PersistentKeepalive = /) {
        sub(/PersistentKeepalive = .*/, "PersistentKeepalive = " newPka, $0)
      } else {
        $0 = $0 "\nPersistentKeepalive = " newPka
      }
    }
    print $0
  } else {
    print $0
  }
}
' "$WG_CONF" > "$TMP_CONF"

mv "$TMP_CONF" "$WG_CONF"

if command -v wg >/dev/null 2>&1; then
  wg set "$WG_IFACE" peer "$CLIENT_PUBLIC_KEY" allowed-ips "$NEW_ALLOWED" || true
  if [ "$UPDATE_PKA" -eq 1 ] && [ -n "$NEW_PKA" ]; then
    wg set "$WG_IFACE" peer "$CLIENT_PUBLIC_KEY" persistent-keepalive "$NEW_PKA" || true
  fi
fi

systemctl restart "wg-quick@$WG_IFACE" || true

echo "Konfigurasi client telah diperbarui."
if command -v wg >/dev/null 2>&1; then
  echo "Status WireGuard saat ini:"
  wg show "$WG_IFACE" 2>/dev/null || echo "(wg tidak dapat menampilkan status)"
fi

