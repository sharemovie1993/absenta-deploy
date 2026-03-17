#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

need_cmd systemctl
need_cmd sed
need_cmd grep

cfg="/etc/redis/redis.conf"
[ -f "$cfg" ] || { echo "Missing: $cfg (install redis first)"; exit 1; }

read -rp "Redis bind IP (WireGuard IP server ini, contoh 10.8.0.11) : " LISTEN_IP
read -rsp "Redis requirepass (input disembunyikan): " REDIS_PASS
echo ""

[ -n "${LISTEN_IP:-}" ] || { echo "LISTEN_IP empty"; exit 1; }
[ -n "${REDIS_PASS:-}" ] || { echo "REDIS_PASS empty"; exit 1; }

ts="$(date +%Y%m%d_%H%M%S)"
as_root cp -a "$cfg" "${cfg}.bak_${ts}"

as_root sed -i -E "s/^#?bind\\s+.*/bind 127.0.0.1 ${LISTEN_IP}/" "$cfg"
as_root sed -i -E "s/^#?protected-mode\\s+.*/protected-mode yes/" "$cfg"
if as_root grep -qE '^#?requirepass ' "$cfg"; then
  as_root sed -i -E "s/^#?requirepass .*/requirepass ${REDIS_PASS}/" "$cfg"
else
  as_root bash -lc "printf '\nrequirepass %s\n' '${REDIS_PASS}' >> '$cfg'"
fi

as_root systemctl restart redis-server
echo "OK configured. Backup: ${cfg}.bak_${ts}"

