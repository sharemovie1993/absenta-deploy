#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

DB_NAME="${DB_NAME:-absensi}"
DB_USER="${DB_USER:-absensi_user}"
DB_PASS="${DB_PASS:-absensi_password_secure}"

read -p "Nama database aplikasi (default ${DB_NAME}): " INPUT_DB_NAME
read -p "Nama user aplikasi (default ${DB_USER}): " INPUT_DB_USER
read -p "Password user aplikasi (default auto gunakan nilai default): " INPUT_DB_PASS

if [ -n "$INPUT_DB_NAME" ]; then
  DB_NAME="$INPUT_DB_NAME"
fi
if [ -n "$INPUT_DB_USER" ]; then
  DB_USER="$INPUT_DB_USER"
fi
if [ -n "$INPUT_DB_PASS" ]; then
  DB_PASS="$INPUT_DB_PASS"
fi

PSQL_AS_POSTGRES="sudo -u postgres psql"

echo "Membuat/menjamin user dan database untuk aplikasi..."
if ! $PSQL_AS_POSTGRES -tAc "\du" | cut -d"|" -f1 | grep -qw "$DB_USER"; then
  $PSQL_AS_POSTGRES -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
else
  echo "User $DB_USER sudah ada, lewati pembuatan user."
fi

if ! $PSQL_AS_POSTGRES -lqt | cut -d"|" -f1 | grep -qw "$DB_NAME"; then
  $PSQL_AS_POSTGRES -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
  $PSQL_AS_POSTGRES -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
else
  echo "Database $DB_NAME sudah ada, lewati pembuatan database."
fi

read -p "Izinkan koneksi dari IP tertentu (bukan hanya localhost)? (y/n, default n): " ALLOW_REMOTE
ALLOW_REMOTE=${ALLOW_REMOTE:-n}

PG_HBA="/etc/postgresql" 
CONF_DIR=$(dirname "$(find /etc/postgresql -maxdepth 3 -type f -name 'postgresql.conf' 2>/dev/null | head -n1)")

if [ "$ALLOW_REMOTE" = "y" ] || [ "$ALLOW_REMOTE" = "Y" ]; then
  if [ -z "$CONF_DIR" ] || [ ! -d "$CONF_DIR" ]; then
    echo "Tidak dapat menemukan direktori konfigurasi PostgreSQL, lewati konfigurasi listen_addresses dan pg_hba."
  else
    PG_CONF="${CONF_DIR}/postgresql.conf"
    PG_HBA_CONF="${CONF_DIR}/pg_hba.conf"

    if [ -f "$PG_CONF" ]; then
      cp "$PG_CONF" "${PG_CONF}.bak.$(date +%Y%m%d%H%M%S)"
      if grep -q "^#listen_addresses" "$PG_CONF" || grep -q "^listen_addresses" "$PG_CONF"; then
        sed -i "s/^#listen_addresses.*/listen_addresses = '*'/" "$PG_CONF" || true
        sed -i "s/^listen_addresses.*/listen_addresses = '*'/" "$PG_CONF" || true
      else
        echo "listen_addresses = '*'" >> "$PG_CONF"
      fi
    fi

    if [ -f "$PG_HBA_CONF" ]; then
      cp "$PG_HBA_CONF" "${PG_HBA_CONF}.bak.$(date +%Y%m%d%H%M%S)"
      read -p "Masukkan CIDR/IP app server yang diizinkan (contoh 10.50.0.0/24 atau 10.50.0.3/32): " APP_CIDR
      if [ -n "$APP_CIDR" ]; then
        echo "Menambahkan aturan di pg_hba.conf untuk $APP_CIDR..."
        echo "host    ${DB_NAME}    ${DB_USER}    ${APP_CIDR}    md5" >> "$PG_HBA_CONF"
      else
        echo "CIDR kosong, lewati perubahan pg_hba.conf."
      fi
    fi
  fi
fi

systemctl restart postgresql

echo "Setup / konfigurasi database server untuk aplikasi selesai."
echo "Database: $DB_NAME, User: $DB_USER"

