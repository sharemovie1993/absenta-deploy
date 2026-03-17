#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

apply_reverse_proxy() { bash "$DIR/role-reverse-proxy.sh"; }
apply_backend() { bash "$DIR/role-backend.sh"; }
apply_postgres() { bash "$DIR/role-postgres.sh"; }
apply_redis() { bash "$DIR/role-redis.sh"; }

while true; do
  echo ""
  echo "=== Role Wizard ==="
  echo "Pilih role server yang mau disiapkan:"
  echo "1) Reverse Proxy (publik)"
  echo "2) Backend (API+Worker / k3s / docker)"
  echo "3) PostgreSQL (VM sekolah)"
  echo "4) Redis (VM sekolah)"
  echo "0) Back"
  read -rp "Pilih: " opt
  case "${opt:-}" in
    1) apply_reverse_proxy ;;
    2) apply_backend ;;
    3) apply_postgres ;;
    4) apply_redis ;;
    0) exit 0 ;;
    *) echo "Pilihan tidak dikenal" ;;
  esac
done

