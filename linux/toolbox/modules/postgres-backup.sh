#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

need_cmd pg_dump
need_cmd gzip

read -rp "DB name: " DB_NAME
read -rp "Output dir [/var/backups/postgresql]: " OUT_DIR
OUT_DIR="${OUT_DIR:-/var/backups/postgresql}"

[ -n "${DB_NAME:-}" ] || { echo "DB_NAME kosong"; exit 1; }
as_root mkdir -p "$OUT_DIR"
as_root chmod 700 "$OUT_DIR" >/dev/null 2>&1 || true

ts="$(date +%Y%m%d_%H%M%S)"
out="${OUT_DIR}/${DB_NAME}_${ts}.sql.gz"

echo "Backup to: $out"
as_root bash -lc "sudo -u postgres pg_dump '${DB_NAME}' | gzip -9 > '${out}'"
as_root chmod 600 "$out" >/dev/null 2>&1 || true
echo "OK"

