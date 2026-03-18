#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

echo "=== Memperbaiki Konfigurasi Networking K3s ==="

# List all interfaces and their IPs
echo "Daftar Interface dan IP yang tersedia di server ini:"
IP_LIST=$(ip -4 -o addr show | awk '{print $2 " -> " $4}' | cut -d'/' -f1)
echo "$IP_LIST"
echo "-----------------------------------------------"

# Try to find wg0 default IP
WG_DEFAULT=$(ip -4 addr show wg0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1 || echo "")

if [ -n "$WG_DEFAULT" ]; then
  read -rp "Pilih IP untuk K3s NodePort (Default wg0: $WG_DEFAULT): " WG_IP
  WG_IP="${WG_IP:-$WG_DEFAULT}"
else
  read -rp "Pilih IP untuk K3s NodePort: " WG_IP
fi

if [ -z "$WG_IP" ]; then
  echo "[!] GAGAL: IP tidak boleh kosong."
  exit 1
fi

echo "IP yang dipilih: $WG_IP"
CONFIG_FILE="/etc/rancher/k3s/config.yaml"

# Pastikan folder config ada
as_root mkdir -p "$(dirname "$CONFIG_FILE")"

# Update atau buat config.yaml
# Kita gunakan node-ip dan bind-address agar K3s hanya bicara lewat WireGuard untuk API dan NodePort
# Ini akan mengatasi masalah port tidak listening di interface yang benar.
cat <<EOF | as_root tee "$CONFIG_FILE" > /dev/null
node-ip: "$WG_IP"
bind-address: "$WG_IP"
disable:
  - traefik
EOF

echo "Konfigurasi $CONFIG_FILE telah diperbarui."
echo "Merestart K3s untuk menerapkan perubahan..."
as_root systemctl restart k3s

echo "Menunggu K3s aktif kembali (10 detik)..."
sleep 10

# Cek apakah sudah listening
echo "Status Listening Ports (NodePort):"
as_root ss -tulpn | grep -E '32001|32080' || echo "Port belum muncul, mungkin manifest belum di-apply."

echo "Done. Silakan jalankan menu Deploy kembali jika port belum muncul."
