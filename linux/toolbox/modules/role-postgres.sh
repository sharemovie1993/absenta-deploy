#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

echo "=== Apply Role: PostgreSQL (VM sekolah) ==="
echo "Ini akan:"
echo "- install PostgreSQL"
echo "- configure listen_addresses untuk IP WireGuard"
echo "- allow subnet WireGuard di pg_hba (scram-sha-256)"
echo "- firewall UFW: allow SSH + WG + allow dari subnet WG ke 5432/tcp"
echo ""

bash "$DIR/postgres-install.sh"

read -rp "WireGuard IP server PostgreSQL ini (contoh 10.8.0.10): " PG_WG_IP
read -rp "WireGuard subnet yang boleh akses (contoh 10.8.0.0/24): " WG_SUBNET
[ -n "${PG_WG_IP:-}" ] || { echo "PG_WG_IP kosong"; exit 1; }
[ -n "${WG_SUBNET:-}" ] || { echo "WG_SUBNET kosong"; exit 1; }

ensure_ufw
as_root ufw default deny incoming >/dev/null
as_root ufw default allow outgoing >/dev/null
as_root ufw allow "${SSH_PORT:-22}/tcp" >/dev/null
as_root ufw allow "$(wg_port)/udp" >/dev/null
as_root ufw allow from "${WG_SUBNET}" to any port 5432 proto tcp >/dev/null
as_root ufw --force enable >/dev/null

export LISTEN_IP="${PG_WG_IP}"
export WG_SUBNET
bash "$DIR/postgres-config-wireguard.sh" <<EOF
${PG_WG_IP}
${WG_SUBNET}
EOF

echo "Done. Next: buat db+user via menu PostgreSQL."

