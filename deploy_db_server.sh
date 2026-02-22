#!/bin/bash
set -e

DB_NAME="${DB_NAME:-absensi}"
DB_USER="${DB_USER:-absensi_user}"
DB_PASS="${DB_PASS:-absensi_password_secure}"

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

echo "Memperbarui paket sistem..."
apt update -y
apt upgrade -y

echo "Menginstall PostgreSQL..."
apt install -y postgresql postgresql-contrib

echo "Mengaktifkan service PostgreSQL..."
systemctl enable postgresql
systemctl start postgresql

echo "Menyiapkan database dan user..."
if ! sudo -u postgres psql -tAc "\du" | cut -d"|" -f1 | grep -qw "$DB_USER"; then
  sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
fi

if ! sudo -u postgres psql -lqt | cut -d"|" -f1 | grep -qw "$DB_NAME"; then
  sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
fi

echo "PostgreSQL siap. Database $DB_NAME dan user $DB_USER telah dikonfigurasi."

