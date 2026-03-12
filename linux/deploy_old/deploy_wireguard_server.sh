#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

echo "=== Deploy WireGuard Server ==="
echo "Script ini akan:"
echo "- Menginstall wireguard dan tools pendukung"
echo "- Membuat konfigurasi dasar /etc/wireguard/wg0.conf jika belum ada"
echo "- Mengaktifkan layanan wg-quick@wg0"
echo ""
read -p "Lanjutkan? (y/n): " CONT
if [ "$CONT" != "y" ]; then
  echo "Batal."
  exit 0
fi

apt-get update -y
apt-get install -y wireguard qrencode

WG_IFACE="wg0"
WG_DIR="/etc/wireguard"
WG_CONF="$WG_DIR/$WG_IFACE.conf"

if [ -f "$WG_CONF" ]; then
  echo "File konfigurasi $WG_CONF sudah ada."
  read -p "Tetap gunakan konfigurasi yang ada dan hanya restart layanan? (y/n): " USE_EXISTING
  if [ "$USE_EXISTING" = "y" ]; then
    systemctl enable "wg-quick@$WG_IFACE"
    systemctl restart "wg-quick@$WG_IFACE"
    systemctl status "wg-quick@$WG_IFACE" --no-pager -l | head -n 20 || true
    echo "WireGuard server diaktifkan ulang menggunakan konfigurasi yang ada."
    exit 0
  else
    cp "$WG_CONF" "$WG_CONF.bak.$(date +%Y%m%d%H%M%S)"
  fi
fi

read -p "IP publik atau hostname server ini (untuk informasi, opsional): " PUBLIC_ENDPOINT
read -p "Port listen WireGuard (default 51820): " WG_PORT
WG_PORT=${WG_PORT:-51820}
read -p "Subnet WireGuard server (default 10.50.0.1/24): " WG_SUBNET
WG_SUBNET=${WG_SUBNET:-10.50.0.1/24}

umask 077
SERVER_PRIV_KEY=$(wg genkey)
SERVER_PUB_KEY=$(printf "%s" "$SERVER_PRIV_KEY" | wg pubkey)

mkdir -p "$WG_DIR"

cat > "$WG_CONF" <<EOF
[Interface]
Address = $WG_SUBNET
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIV_KEY
SaveConfig = true

# Tambahkan peer client menggunakan script add_wireguard_client.sh
EOF

chmod 600 "$WG_CONF"

systemctl enable "wg-quick@$WG_IFACE"
systemctl restart "wg-quick@$WG_IFACE"

echo ""
echo "WireGuard server telah dikonfigurasi."
echo "Interface  : $WG_IFACE"
echo "ListenPort : $WG_PORT"
echo "Address    : $WG_SUBNET"
if [ -n "$PUBLIC_ENDPOINT" ]; then
  echo "Endpoint   : $PUBLIC_ENDPOINT:$WG_PORT"
fi
echo ""
echo "PublicKey server:"
echo "$SERVER_PUB_KEY"
echo ""
echo "Gunakan script add_wireguard_client.sh untuk menambahkan client baru."

