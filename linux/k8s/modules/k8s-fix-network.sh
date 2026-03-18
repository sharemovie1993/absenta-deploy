#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

echo "=== Memperbaiki Konfigurasi Networking K3s ==="

WG_INTERFACE="${WG_INTERFACE:-wg0}"
WG_IP=$(ip -4 addr show "$WG_INTERFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "")

if [ -z "$WG_IP" ]; then
  echo "[!] GAGAL: Interface $WG_INTERFACE tidak ditemukan. Tidak bisa memperbaiki binding."
  exit 1
fi

echo "Ditemukan IP WireGuard: $WG_IP"
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
