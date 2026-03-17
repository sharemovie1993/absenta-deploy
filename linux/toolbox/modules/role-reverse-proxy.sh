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
as_root ufw default deny incoming >/dev/null
as_root ufw default allow outgoing >/dev/null
as_root ufw allow "${SSH_PORT:-22}/tcp" >/dev/null
as_root ufw allow 80/tcp >/dev/null
as_root ufw allow 443/tcp >/dev/null
as_root ufw allow "$(wg_port)/udp" >/dev/null
as_root ufw --force enable >/dev/null
echo "OK firewall baseline"

if [ "${ans,,}" = "y" ]; then
  bash "$DIR/hardening-basic.sh"
  bash "$DIR/time-sync.sh"
fi

echo "Done. Next: WireGuard menu untuk memastikan tunnel aktif."

