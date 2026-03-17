#!/usr/bin/env bash
set -euo pipefail

need_cmd redis-cli

read -rp "Redis host (WG IP): " HOST
read -rp "Redis port [6379]: " PORT
PORT="${PORT:-6379}"
read -rsp "Redis password (input disembunyikan): " PASS
echo ""

[ -n "${HOST:-}" ] || { echo "HOST kosong"; exit 1; }

redis-cli -h "$HOST" -p "$PORT" -a "$PASS" ping | grep -q PONG
echo "OK redis ping"

