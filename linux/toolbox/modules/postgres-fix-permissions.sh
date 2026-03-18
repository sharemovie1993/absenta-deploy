#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

echo "=== Perbaikan Izin Database (PostgreSQL) ==="

DB_NAME="absensi"
DB_USER="absenta_user"

echo "--> Memberikan izin penuh untuk user '$DB_USER' pada database '$DB_NAME'..."

# PostgreSQL 15+ (v17/18) butuh izin eksplisit pada SCHEMA public
as_root sudo -u postgres psql -d "$DB_NAME" <<EOF
-- Jadikan user pemilik database (agar punya hak CREATE)
ALTER DATABASE "$DB_NAME" OWNER TO $DB_USER;

-- Berikan izin pada skema public
GRANT ALL ON SCHEMA public TO $DB_USER;
ALTER SCHEMA public OWNER TO $DB_USER;

-- Izin pada objek yang sudah ada
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO $DB_USER;

-- Izin otomatis untuk objek di masa depan
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO $DB_USER;

-- Tambahan: Izin eksplisit untuk CREATE di skema public
GRANT CREATE ON SCHEMA public TO $DB_USER;
EOF

echo "OK: Izin database telah diperbarui."
