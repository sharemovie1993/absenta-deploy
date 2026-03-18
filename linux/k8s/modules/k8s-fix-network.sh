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

# Validasi IP apakah benar-benar ada di interface sistem (Pencocokan Presisi)
if ! ip -4 addr show | grep -qw "$WG_IP"; then
  echo "[!] GAGAL: IP $WG_IP tidak ditemukan di interface manapun di server ini!"
  echo "Pastikan Bapak mengetik IP dengan benar tanpa spasi."
  exit 1
fi

echo "IP yang dipilih: $WG_IP"
CONFIG_FILE="/etc/rancher/k3s/config.yaml"
BACKUP_FILE="${CONFIG_FILE}.bak"

# Backup config lama jika ada
if [ -f "$CONFIG_FILE" ]; then
  as_root cp "$CONFIG_FILE" "$BACKUP_FILE"
fi

echo "Memperbarui konfigurasi di $CONFIG_FILE..."
cat <<EOF | as_root tee "$CONFIG_FILE" > /dev/null
node-ip: "$WG_IP"
bind-address: "$WG_IP"
disable:
  - traefik
EOF

echo "Merestart K3s (dengan timeout 30 detik)..."
# Gunakan --no-block agar tidak stuck jika service macet saat stop
as_root systemctl restart k3s --no-block || true

echo "Menunggu K3s aktif kembali..."
ITER=0
MAX_ITER=15 # 30 detik total (15 * 2s)
SUCCESS=false

while [ $ITER -lt $MAX_ITER ]; do
  if as_root systemctl is-active k3s >/dev/null 2>&1; then
    echo "[OK] K3s sudah Aktif (Running)."
    SUCCESS=true
    break
  fi
  echo "   ... Menunggu ($((ITER+1))/$MAX_ITER)"
  sleep 2
  ITER=$((ITER+1))
done

if [ "$SUCCESS" = "false" ]; then
  echo "[!] K3s gagal start tepat waktu. Menampilkan log 20 baris terakhir:"
  as_root journalctl -u k3s --no-pager -n 20
  echo ""
  echo "Mencoba mengembalikan konfigurasi lama..."
  if [ -f "$BACKUP_FILE" ]; then
    as_root mv "$BACKUP_FILE" "$CONFIG_FILE"
    as_root systemctl restart k3s --no-block
  fi
  exit 1
fi

# Cek apakah sudah listening
echo "Verifikasi Listening Ports (NodePort):"
as_root ss -tulpn | grep -E '32001|32080' || echo "   [!] Port belum muncul di 'ss -tulpn'. Mungkin manifest belum di-apply atau ada kendala lain."

echo "Perbaikan Selesai."
