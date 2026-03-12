#!/bin/bash
set -e

# Script ini dijalankan di server yang menjalankan Backend (App Server)
# Fungsinya untuk mengkonfigurasi SMTP pada aplikasi Absenta Backend

APP_ROOT="${APP_ROOT:-/var/www/absenta}"
BACKEND_DIR="$APP_ROOT/backend"
ENV_FILE="$BACKEND_DIR/.env"

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

echo "=== Konfigurasi SMTP Aplikasi Backend ==="

if [ ! -f "$ENV_FILE" ]; then
  echo "Error: File .env tidak ditemukan di $ENV_FILE"
  read -p "Masukkan path direktori backend manual (contoh: /var/www/absenta/backend): " MANUAL_DIR
  if [ -z "$MANUAL_DIR" ]; then
    echo "Path tidak boleh kosong."
    exit 1
  fi
  BACKEND_DIR="$MANUAL_DIR"
  ENV_FILE="$BACKEND_DIR/.env"
  if [ ! -f "$ENV_FILE" ]; then
    echo "Error: File .env tetap tidak ditemukan di $ENV_FILE"
    exit 1
  fi
fi

echo "Menggunakan file konfigurasi: $ENV_FILE"
echo ""
echo "Silakan masukkan detail SMTP Mail Server Anda."
echo "Biasanya host: mail.domainanda.com, Port: 587 (TLS)"
echo ""

# Ambil nilai lama jika ada
OLD_SMTP_HOST=$(grep "^SMTP_HOST=" "$ENV_FILE" | cut -d '=' -f2 || echo "")
OLD_SMTP_PORT=$(grep "^SMTP_PORT=" "$ENV_FILE" | cut -d '=' -f2 || echo "")
OLD_SMTP_USER=$(grep "^SMTP_USER=" "$ENV_FILE" | cut -d '=' -f2 || echo "")
OLD_SMTP_FROM=$(grep "^SMTP_FROM_EMAIL=" "$ENV_FILE" | cut -d '=' -f2 || echo "")

read -p "SMTP Host [${OLD_SMTP_HOST:-mail.absenta.id}]: " SMTP_HOST
SMTP_HOST=${SMTP_HOST:-${OLD_SMTP_HOST:-mail.absenta.id}}

read -p "SMTP Port [${OLD_SMTP_PORT:-587}]: " SMTP_PORT
SMTP_PORT=${SMTP_PORT:-${OLD_SMTP_PORT:-587}}

read -p "SMTP User (Email Lengkap) [${OLD_SMTP_USER:-no-reply@absenta.id}]: " SMTP_USER
SMTP_USER=${SMTP_USER:-${OLD_SMTP_USER:-no-reply@absenta.id}}

read -s -p "SMTP Password: " SMTP_PASS
echo ""

read -p "Sender Email (From) [${OLD_SMTP_FROM:-$SMTP_USER}]: " SMTP_FROM_EMAIL
SMTP_FROM_EMAIL=${SMTP_FROM_EMAIL:-${OLD_SMTP_FROM:-$SMTP_USER}}

read -p "Sender Name (From Name) [Sistem Absensi]: " SMTP_FROM_NAME
SMTP_FROM_NAME=${SMTP_FROM_NAME:-"Sistem Absensi"}

# Konfirmasi
echo ""
echo "Detail Konfigurasi:"
echo "Host: $SMTP_HOST"
echo "Port: $SMTP_PORT"
echo "User: $SMTP_USER"
echo "From: $SMTP_FROM_NAME <$SMTP_FROM_EMAIL>"
echo ""
read -p "Simpan konfigurasi ini? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
  echo "Dibatalkan."
  exit 0
fi

# Fungsi helper untuk update atau tambah env var
update_env() {
  local key=$1
  local value=$2
  if grep -q "^${key}=" "$ENV_FILE"; then
    # Escape special characters for sed
    # We use | as delimiter, assuming value doesn't contain |
    # If value contains special chars, this might be tricky.
    # Simple approach: escape / and &
    escaped_value=$(printf '%s\n' "$value" | sed -e 's/[\/&]/\\&/g')
    sed -i "s|^${key}=.*|${key}=${escaped_value}|" "$ENV_FILE"
  else
    echo "${key}=${value}" >> "$ENV_FILE"
  fi
}

echo "Menyimpan konfigurasi..."

# Update SMTP_HOST
update_env "SMTP_HOST" "$SMTP_HOST"
update_env "EMAIL_HOST" "$SMTP_HOST"

# Update SMTP_PORT
update_env "SMTP_PORT" "$SMTP_PORT"
update_env "EMAIL_PORT" "$SMTP_PORT"

# Update SMTP_USER
update_env "SMTP_USER" "$SMTP_USER"
update_env "EMAIL_USER" "$SMTP_USER"

# Update SMTP_PASS
update_env "SMTP_PASS" "$SMTP_PASS"
update_env "EMAIL_PASS" "$SMTP_PASS"

# Update SMTP_FROM
update_env "SMTP_FROM_EMAIL" "$SMTP_FROM_EMAIL"
update_env "EMAIL_FROM" "$SMTP_FROM_EMAIL"
update_env "SMTP_FROM_NAME" "$SMTP_FROM_NAME"

# Update SMTP_SECURE
if [ "$SMTP_PORT" = "465" ]; then
  update_env "SMTP_SECURE" "true"
  update_env "EMAIL_SECURE" "true"
else
  update_env "SMTP_SECURE" "false"
  update_env "EMAIL_SECURE" "false"
fi

echo "Konfigurasi tersimpan."

# Restart Backend
echo "Merestart layanan backend (PM2: absenta-backend)..."
if command -v pm2 >/dev/null 2>&1; then
  pm2 reload absenta-backend || pm2 restart absenta-backend || echo "Gagal restart PM2. Silakan restart manual."
else
  echo "PM2 tidak ditemukan. Silakan restart aplikasi backend secara manual."
fi

echo "Selesai."
