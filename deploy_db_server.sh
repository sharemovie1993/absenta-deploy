#!/bin/bash
set -e

DB_NAME="${DB_NAME:-absensi}"
DB_USER="${DB_USER:-absensi_user}"
DB_PASS="${DB_PASS:-absensi_password_secure}"
POSTGRES_VERSION="${POSTGRES_VERSION:-17}"

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

echo "Memperbarui paket sistem..."
apt update -y
apt upgrade -y

echo "Menginstall PostgreSQL..."
if ! apt-cache show "postgresql-${POSTGRES_VERSION}" >/dev/null 2>&1; then
  echo "Paket postgresql-${POSTGRES_VERSION} belum tersedia, menambahkan repository PostgreSQL resmi."
  if command -v lsb_release >/dev/null 2>&1; then
    CODENAME="$(lsb_release -cs)"
  elif [ -f /etc/os-release ]; then
    . /etc/os-release
    CODENAME="$VERSION_CODENAME"
  else
    CODENAME=""
  fi
  apt install -y wget gnupg2 ca-certificates
  wget -qO- https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
  if [ -n "$CODENAME" ]; then
    echo "deb http://apt.postgresql.org/pub/repos/apt ${CODENAME}-pgdg main" >/etc/apt/sources.list.d/pgdg.list
  else
    echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" >/etc/apt/sources.list.d/pgdg.list || true
  fi
  apt update -y
fi
apt install -y "postgresql-${POSTGRES_VERSION}" "postgresql-client-${POSTGRES_VERSION}" postgresql-contrib

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
