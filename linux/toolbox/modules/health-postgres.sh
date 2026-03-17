#!/usr/bin/env bash
set -euo pipefail

need_cmd psql

read -rp "Postgres host (WG IP): " HOST
read -rp "Postgres port [5432]: " PORT
PORT="${PORT:-5432}"
read -rp "DB name: " DB
read -rp "DB user: " USER
read -rsp "DB password (input disembunyikan): " PASS
echo ""

[ -n "${HOST:-}" ] || { echo "HOST kosong"; exit 1; }
[ -n "${DB:-}" ] || { echo "DB kosong"; exit 1; }
[ -n "${USER:-}" ] || { echo "USER kosong"; exit 1; }

export PGPASSWORD="$PASS"
psql "host=${HOST} port=${PORT} dbname=${DB} user=${USER} sslmode=disable" -v ON_ERROR_STOP=1 -c "SELECT now();" >/dev/null
unset PGPASSWORD
echo "OK postgres connect"

