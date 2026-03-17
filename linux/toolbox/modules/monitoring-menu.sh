#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

run_node_exporter_install() { echo "--> Memasang Node Exporter..."; bash "$DIR/node-exporter-install.sh"; }
run_node_exporter_status() { echo "--> Memeriksa status Node Exporter..."; bash "$DIR/node-exporter-status.sh"; }
run_health_wg_ping() { echo "--> Mengetes ping via WireGuard..."; bash "$DIR/health-wg-ping.sh"; }
run_health_pg() { echo "--> Mengetes koneksi PostgreSQL..."; bash "$DIR/health-postgres.sh"; }
run_health_redis() { echo "--> Mengetes koneksi Redis..."; bash "$DIR/health-redis.sh"; }
run_backup_schedule() { echo "--> Mengatur jadwal backup PostgreSQL..."; bash "$DIR/postgres-backup-schedule.sh"; }
run_pg_exporter() { echo "--> Menjalankan PostgreSQL Exporter (Metrics)..."; bash "$DIR/postgres-status.sh"; }
run_redis_exporter() { echo "--> Menjalankan Redis Exporter (Metrics)..."; bash "$DIR/redis-status.sh"; }

while true; do
  echo ""
  echo "=== Monitoring & Health Menu ==="
  echo "1) Install Node Exporter (Metrics Sistem)"
  echo "2) Status Node Exporter"
  echo "3) Health: Ping IP via WireGuard"
  echo "4) Health: PostgreSQL Connect Test"
  echo "5) Health: Redis Ping Test"
  echo "6) Status: PostgreSQL Runtime Stats"
  echo "7) Status: Redis Runtime Stats"
  echo "8) Schedule: PostgreSQL Backup Harian + Rotasi"
  echo "0) Kembali"
  read -rp "Pilih: " opt
  case "${opt:-}" in
    1) run_node_exporter_install ;;
    2) run_node_exporter_status ;;
    3) run_health_wg_ping ;;
    4) run_health_pg ;;
    5) run_health_redis ;;
    6) run_pg_exporter ;;
    7) run_redis_exporter ;;
    8) run_backup_schedule ;;
    0) exit 0 ;;
    *) echo "Pilihan tidak dikenal" ;;
  esac
done

