#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

run_install() { bash "$DIR/postgres-install.sh"; }
run_status() { bash "$DIR/postgres-status.sh"; }
run_config_wg() { bash "$DIR/postgres-config-wireguard.sh"; }
run_create_db_user() { bash "$DIR/postgres-create-db-user.sh"; }
run_backup() { bash "$DIR/postgres-backup.sh"; }
run_restore() { bash "$DIR/postgres-restore.sh"; }

while true; do
  echo ""
  echo "=== PostgreSQL Menu ==="
  echo "1) Install PostgreSQL"
  echo "2) Status (systemctl + psql version)"
  echo "3) Configure listen + pg_hba for WireGuard subnet"
  echo "4) Create database + user (grant privileges)"
  echo "5) Backup database (pg_dump)"
  echo "6) Restore database (psql < dump)"
  echo "0) Back"
  read -rp "Pilih: " opt
  case "${opt:-}" in
    1) run_install ;;
    2) run_status ;;
    3) run_config_wg ;;
    4) run_create_db_user ;;
    5) run_backup ;;
    6) run_restore ;;
    0) exit 0 ;;
    *) echo "Pilihan tidak dikenal" ;;
  esac
done
