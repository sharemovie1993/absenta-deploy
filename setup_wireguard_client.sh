#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

echo "Memperbarui paket sistem..."
apt update -y
apt upgrade -y

echo "Menginstall WireGuard dan dependensi..."
apt install -y wireguard wireguard-tools resolvconf

WG_DIR="/etc/wireguard"
mkdir -p "$WG_DIR"

read -p "Nama interface WireGuard (default wg0): " WG_IFACE
WG_IFACE=${WG_IFACE:-wg0}

WG_CONF="$WG_DIR/$WG_IFACE.conf"

if [ -f "$WG_CONF" ]; then
  read -p "Config $WG_CONF sudah ada. Overwrite? (y/n): " OVERWRITE
  if [ "$OVERWRITE" != "y" ]; then
    echo "Batal mengubah konfigurasi WireGuard."
    exit 0
  fi
fi

echo "Menghasilkan private key client..."
CLIENT_PRIVATE_KEY=$(wg genkey)
CLIENT_PUBLIC_KEY=$(printf "%s" "$CLIENT_PRIVATE_KEY" | wg pubkey)

echo "Public key client:"
echo "$CLIENT_PUBLIC_KEY"

read -p "Alamat IP client di jaringan VPN (contoh 10.8.0.2/32): " CLIENT_ADDRESS
read -p "Public key server: " SERVER_PUBLIC_KEY
read -p "Endpoint server (host:port, contoh vpn.example.com:51820): " SERVER_ENDPOINT
read -p "Allowed IPs (contoh 10.8.0.0/24 atau 0.0.0.0/0): " ALLOWED_IPS
read -p "DNS untuk interface ini (opsional, contoh 1.1.1.1): " DNS_ADDR

umask 077

{
  echo "[Interface]"
  echo "PrivateKey = $CLIENT_PRIVATE_KEY"
  echo "Address = $CLIENT_ADDRESS"
  if [ -n "$DNS_ADDR" ]; then
    echo "DNS = $DNS_ADDR"
  fi
  echo ""
  echo "[Peer]"
  echo "PublicKey = $SERVER_PUBLIC_KEY"
  echo "Endpoint = $SERVER_ENDPOINT"
  echo "AllowedIPs = $ALLOWED_IPS"
  echo "PersistentKeepalive = 25"
} > "$WG_CONF"

chmod 600 "$WG_CONF"

echo "Mengaktifkan interface WireGuard $WG_IFACE..."
systemctl enable "wg-quick@$WG_IFACE"
systemctl restart "wg-quick@$WG_IFACE"

echo "Status WireGuard:"
wg show "$WG_IFACE" || true

echo "Setup WireGuard client selesai."

