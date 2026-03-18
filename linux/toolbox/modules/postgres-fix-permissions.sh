#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

echo "=== Perbaikan Izin Database (PostgreSQL) ==="

DB_NAME="absensi"
DB_USER="absenta_user"

echo "--> Memberikan izin penuh untuk user '$DB_USER' pada database '$DB_NAME'..."

as_root sudo -u postgres psql -d "$DB_NAME" <<EOF
-- 1. Berikan hak Superuser sementara agar migrasi lancar
ALTER USER $DB_USER WITH SUPERUSER;

-- 2. Bersihkan catatan migrasi yang gagal (P3009 FIX)
DELETE FROM "_prisma_migrations" WHERE migration_name = '20260308081750_add_invoice_public_token';
DROP TABLE IF EXISTS "InvoicePublicToken" CASCADE;

-- 3. Jadikan user pemilik database dan skema
ALTER DATABASE "$DB_NAME" OWNER TO $DB_USER;
ALTER SCHEMA public OWNER TO $DB_USER;
GRANT ALL ON SCHEMA public TO $DB_USER;
GRANT CREATE ON SCHEMA public TO $DB_USER;

-- 4. Izin pada objek yang sudah ada & masa depan
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO $DB_USER;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO $DB_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO $DB_USER;
EOF

echo "OK: Database telah dibersihkan dari migrasi gagal dan izin ditingkatkan."

echo "OK: Izin database telah diperbarui."
