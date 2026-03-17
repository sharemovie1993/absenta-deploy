#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

echo "=== Apply Role: Backend (API+Worker) ==="
echo "Ini akan:"
echo "- install & enable UFW (safe defaults)"
echo "- allow SSH dan WireGuard UDP"
echo "- allow akses API NodePort dari reverse proxy via WireGuard (opsional)"
echo "- install chrony + fail2ban (opsional hardening basic)"
echo ""

ensure_ufw
as_root ufw default deny incoming >/dev/null
as_root ufw default allow outgoing >/dev/null
as_root ufw allow "${SSH_PORT:-22}/tcp" >/dev/null
as_root ufw allow "$(wg_port)/udp" >/dev/null

read -rp "Reverse proxy WG IP (contoh 10.8.0.2) [skip untuk lewati]: " RP_WG_IP
if [ -n "${RP_WG_IP:-}" ]; then
  read -rp "Backend API NodePort [32001]: " NP
  NP="${NP:-32001}"
  as_root ufw allow from "${RP_WG_IP}" to any port "${NP}" proto tcp >/dev/null
  echo "OK allow from ${RP_WG_IP} to ${NP}/tcp"
fi

as_root ufw --force enable >/dev/null
echo "OK firewall baseline"

read -rp "Jalankan hardening basic juga? (y/n) [y]: " ans
ans="${ans:-y}"
if [ "${ans,,}" = "y" ]; then
  bash "$DIR/hardening-basic.sh"
  bash "$DIR/time-sync.sh"
fi

echo "Done. Next: jalankan deploy (docker/k3s) dan pastikan DB/Redis via WG."

