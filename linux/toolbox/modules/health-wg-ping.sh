#!/usr/bin/env bash
set -euo pipefail

need_cmd ping

read -rp "Target IP (contoh 10.8.0.10): " IP
[ -n "${IP:-}" ] || { echo "IP kosong"; exit 1; }

echo "Pinging ${IP}..."
ping -c 3 "$IP"
echo "OK"

