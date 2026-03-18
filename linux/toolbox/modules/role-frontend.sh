#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

echo "=== Role Setup: Frontend (Web UI) ==="
echo "Skrip ini akan mengatur firewall agar server bisa diakses oleh Reverse Proxy."

apt_ensure ufw

# Ambil konfigurasi port (default 32000 untuk k3s frontend)
# Karena skrip ini di toolbox, kita load env dengan cara toolbox
# load_env_files biasanya ada di k8s common, untuk toolbox kita cukup ambil nilai default
NP="32000"

as_root ufw default deny incoming
as_root ufw default allow outgoing
as_root ufw allow "${SSH_PORT:-22}/tcp"

read -rp "Reverse proxy WG IP (contoh 10.60.0.2) [kosongkan untuk izinkan semua WG]: " RP_WG_IP
if [ -n "${RP_WG_IP:-}" ]; then
  as_root ufw allow from "${RP_WG_IP}" to any port "${NP}" proto tcp
  echo "OK: Hanya allow dari ${RP_WG_IP} ke port ${NP}"
else
  # Jika kosong, izinkan dari seluruh subnet WireGuard (biasanya 10.60.0.0/24)
  WG_SUB=$(as_root wg show 2>/dev/null | grep "interface:" -A 10 | grep "address" | awk '{print $2}' | cut -d'.' -f1-3)".0/24"
  WG_SUB="${WG_SUB:-10.60.0.0/24}"
  as_root ufw allow from "${WG_SUB}" to any port "${NP}" proto tcp
  echo "OK: Allow dari seluruh subnet ${WG_SUB} ke port ${NP}"
fi

as_root ufw --force enable
echo "=== Frontend Role Applied ==="
