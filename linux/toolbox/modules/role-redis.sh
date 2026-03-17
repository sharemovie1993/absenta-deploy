#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

echo "=== Apply Role: Redis (VM sekolah) ==="
echo "Ini akan:"
echo "- install Redis"
echo "- configure bind untuk IP WireGuard + requirepass"
echo "- firewall UFW: allow SSH + WG + allow dari subnet WG ke 6379/tcp"
echo ""

bash "$DIR/redis-install.sh"

read -rp "WireGuard IP server Redis ini (contoh 10.8.0.11): " REDIS_WG_IP
read -rp "WireGuard subnet yang boleh akses (contoh 10.8.0.0/24): " WG_SUBNET
[ -n "${REDIS_WG_IP:-}" ] || { echo "REDIS_WG_IP kosong"; exit 1; }
[ -n "${WG_SUBNET:-}" ] || { echo "WG_SUBNET kosong"; exit 1; }

ensure_ufw
as_root ufw default deny incoming
as_root ufw default allow outgoing
as_root ufw allow "${SSH_PORT:-22}/tcp"
as_root ufw allow "$(wg_port)/udp"
as_root ufw allow from "${WG_SUBNET}" to any port 6379 proto tcp
as_root ufw --force enable

echo "Sekarang konfigurasi redis.conf (bind + requirepass)."
bash "$DIR/redis-config-wireguard.sh"

echo "Done."

