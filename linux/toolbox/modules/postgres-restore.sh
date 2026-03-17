#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

need_cmd gunzip
need_cmd psql

read -rp "DB name target: " DB_NAME
read -rp "Path dump .sql.gz: " DUMP_PATH

[ -n "${DB_NAME:-}" ] || { echo "DB_NAME kosong"; exit 1; }
[ -f "${DUMP_PATH:-}" ] || { echo "Dump tidak ditemukan"; exit 1; }

echo "Restore akan overwrite data di DB: ${DB_NAME}"
echo "Ketik APPLY untuk lanjut:"
read -r CONFIRM
if [ "${CONFIRM:-}" != "APPLY" ]; then
  echo "Batal"
  exit 0
fi

as_root bash -lc "sudo -u postgres psql -v ON_ERROR_STOP=1 -d '${DB_NAME}' -c 'SELECT 1' >/dev/null"
as_root bash -lc "gunzip -c '${DUMP_PATH}' | sudo -u postgres psql -v ON_ERROR_STOP=1 -d '${DB_NAME}'"
echo "OK restore"

