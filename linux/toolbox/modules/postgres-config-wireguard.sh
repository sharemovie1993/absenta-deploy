#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

need_cmd systemctl
need_cmd sed
need_cmd grep

if ! is_cmd psql; then
  echo "psql not found. Install PostgreSQL first."
  exit 1
fi

ver_dir="$(as_root bash -lc "ls -1 /etc/postgresql 2>/dev/null | sort -V | tail -n 1" || true)"
[ -n "${ver_dir:-}" ] || { echo "Could not detect /etc/postgresql/<version> (is postgres installed?)"; exit 1; }

conf_dir="/etc/postgresql/${ver_dir}/main"
postgresql_conf="${conf_dir}/postgresql.conf"
pg_hba_conf="${conf_dir}/pg_hba.conf"

[ -f "$postgresql_conf" ] || { echo "Missing: $postgresql_conf"; exit 1; }
[ -f "$pg_hba_conf" ] || { echo "Missing: $pg_hba_conf"; exit 1; }

read -rp "PostgreSQL listen IP (WireGuard IP server ini, contoh 10.8.0.10) : " LISTEN_IP
read -rp "WireGuard subnet yang boleh akses (contoh 10.8.0.0/24) : " WG_SUBNET

[ -n "${LISTEN_IP:-}" ] || { echo "LISTEN_IP empty"; exit 1; }
[ -n "${WG_SUBNET:-}" ] || { echo "WG_SUBNET empty"; exit 1; }

ts="$(date +%Y%m%d_%H%M%S)"
as_root cp -a "$postgresql_conf" "${postgresql_conf}.bak_${ts}"
as_root cp -a "$pg_hba_conf" "${pg_hba_conf}.bak_${ts}"

as_root sed -i -E "s/^#?listen_addresses\\s*=\\s*.*/listen_addresses = '${LISTEN_IP},localhost'/" "$postgresql_conf"

marker="# absenta-wireguard"
rule="host    all             all             ${WG_SUBNET}            scram-sha-256"
if ! as_root grep -qF "$marker" "$pg_hba_conf"; then
  as_root bash -lc "printf '\n%s\n%s\n' '$marker' '$rule' >> '$pg_hba_conf'"
fi

as_root systemctl restart postgresql
echo "OK configured. Backups:"
echo "- ${postgresql_conf}.bak_${ts}"
echo "- ${pg_hba_conf}.bak_${ts}"

