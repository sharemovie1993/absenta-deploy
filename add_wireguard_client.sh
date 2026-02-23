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

read -p "Nama client (label, misal app-server): " CLIENT_NAME
read -p "Public key client: " CLIENT_PUBLIC_KEY
read -p "Alamat IP client di jaringan VPN (contoh 10.8.0.2/32): " CLIENT_ADDRESS
read -p "Allowed IPs untuk client ini (default sama dengan alamat client): " CLIENT_ALLOWED_IPS

if [ -z "$CLIENT_PUBLIC_KEY" ] || [ -z "$CLIENT_ADDRESS" ]; then
  echo "Public key dan alamat client wajib diisi."
  exit 1
fi

if [ -z "$CLIENT_ALLOWED_IPS" ]; then
  CLIENT_ALLOWED_IPS="$CLIENT_ADDRESS"
fi

read -p "Persistent keepalive (detik, default 25, kosongkan untuk disable): " PKA

cp "$WG_CONF" "${WG_CONF}.bak.$(date +%Y%m%d%H%M%S)"

{
  echo ""
  echo "[Peer]"
  echo "PublicKey = $CLIENT_PUBLIC_KEY"
  echo "AllowedIPs = $CLIENT_ALLOWED_IPS"
  if [ -n "$PKA" ]; then
    echo "PersistentKeepalive = $PKA"
  else
    echo "PersistentKeepalive = 25"
  fi
} >> "$WG_CONF"

if ! systemctl is-active --quiet "wg-quick@$WG_IFACE"; then
  systemctl start "wg-quick@$WG_IFACE"
fi

wg set "$WG_IFACE" peer "$CLIENT_PUBLIC_KEY" allowed-ips "$CLIENT_ALLOWED_IPS" || true

if [ -n "$PKA" ]; then
  wg set "$WG_IFACE" peer "$CLIENT_PUBLIC_KEY" persistent-keepalive "$PKA" || true
fi

echo "Peer baru telah ditambahkan untuk client: $CLIENT_NAME"
echo "Status WireGuard:"
wg show "$WG_IFACE" || true

