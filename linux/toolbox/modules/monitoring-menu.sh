#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

run_node_exporter_install() { bash "$DIR/node-exporter-install.sh"; }
run_node_exporter_status() { bash "$DIR/node-exporter-status.sh"; }
run_health_wg_ping() { bash "$DIR/health-wg-ping.sh"; }
run_health_pg() { bash "$DIR/health-postgres.sh"; }
run_health_redis() { bash "$DIR/health-redis.sh"; }
run_backup_schedule() { bash "$DIR/postgres-backup-schedule.sh"; }

while true; do
  echo ""
  echo "=== Monitoring & Health Menu ==="
  echo "1) Install Node Exporter (metrics)"
  echo "2) Status Node Exporter"
  echo "3) Health: ping IP via WireGuard"
  echo "4) Health: PostgreSQL connect test"
  echo "5) Health: Redis ping test"
  echo "6) Schedule: PostgreSQL backup harian + rotasi"
  echo "0) Back"
  read -rp "Pilih: " opt
  case "${opt:-}" in
    1) run_node_exporter_install ;;
    2) run_node_exporter_status ;;
    3) run_health_wg_ping ;;
    4) run_health_pg ;;
    5) run_health_redis ;;
    6) run_backup_schedule ;;
    0) exit 0 ;;
    *) echo "Pilihan tidak dikenal" ;;
  esac
done

