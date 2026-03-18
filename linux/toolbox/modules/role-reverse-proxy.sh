#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

echo "=== Apply Role: Reverse Proxy ==="
echo "Ini akan:"
echo "- install & enable UFW (safe defaults)"
echo "- allow SSH, 80/443, dan WireGuard UDP"
echo "- install chrony + fail2ban (opsional hardening basic)"
echo ""

read -rp "Jalankan hardening basic juga? (y/n) [y]: " ans
ans="${ans:-y}"

ensure_ufw
as_root ufw default deny incoming
as_root ufw default allow outgoing
as_root ufw allow "${SSH_PORT:-22}/tcp"
as_root ufw allow 80/tcp
as_root ufw allow 443/tcp
as_root ufw allow "$(wg_port)/udp"
as_root ufw --force enable
echo "OK firewall baseline"

if [ "${ans,,}" = "y" ]; then
  bash "$DIR/hardening-basic.sh"
  bash "$DIR/time-sync.sh"
fi

echo ""
echo "=== Nginx Upstream Wizard ==="
echo "Gunakan info ini untuk config Nginx di server Reverse Proxy ini."

read -rp "IP K3s Node (WireGuard) [10.60.0.1]: " node_ip
node_ip="${node_ip:-10.60.0.1}"

read -rp "Setup upstream untuk Backend? (y/n) [y]: " do_backend
if [ "${do_backend,,}" != "n" ]; then
  read -rp "Port Backend NodePort [32001]: " b_port
  b_port="${b_port:-32001}"
  echo ">>> [CONFIG] upstream absenta_backend { server $node_ip:$b_port; }"
fi

read -rp "Setup upstream untuk Frontend? (y/n) [n]: " do_frontend
if [ "${do_frontend,,}" = "y" ]; then
  read -rp "Port Frontend NodePort [32080]: " f_port
  f_port="${f_port:-32080}"
  echo ">>> [CONFIG] upstream absenta_frontend { server $node_ip:$f_port; }"
fi

echo ""
echo "Done. Next: WireGuard menu untuk memastikan tunnel aktif."

