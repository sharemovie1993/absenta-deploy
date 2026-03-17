#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

need_cmd psql

read -rp "DB name (contoh absenta): " DB_NAME
read -rp "DB user (contoh absenta_app): " DB_USER
read -rsp "DB password (input disembunyikan): " DB_PASS
echo ""

[ -n "${DB_NAME:-}" ] || { echo "DB_NAME empty"; exit 1; }
[ -n "${DB_USER:-}" ] || { echo "DB_USER empty"; exit 1; }
[ -n "${DB_PASS:-}" ] || { echo "DB_PASS empty"; exit 1; }

as_root bash -lc "sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
DO \\\$\\\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
    CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASS}';
  END IF;
END
\\\$\\\$;

DO \\\$\\\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_NAME}') THEN
    CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};
  END IF;
END
\\\$\\\$;

GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
SQL"

echo "OK created/ensured: db=${DB_NAME}, user=${DB_USER}"

