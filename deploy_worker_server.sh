#!/bin/bash
set -e

APP_ROOT="${APP_ROOT:-/var/www/absenta}"
BACKEND_DIR="$APP_ROOT/backend"

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

echo "Memperbarui paket sistem..."
apt update -y
apt upgrade -y

echo "Menginstall paket dasar..."
apt install -y curl git build-essential postgresql-client redis-tools

echo "Memeriksa Node.js 18..."
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
  apt install -y nodejs
fi

echo "Menginstall PM2..."
if ! command -v pm2 >/dev/null 2>&1; then
  npm install -g pm2
fi

mkdir -p "$APP_ROOT"

if [ ! -d "$BACKEND_DIR/.git" ]; then
  echo "Repository backend belum ada."
  read -p "Masukkan URL repository backend (https): " BACKEND_REPO_URL
  if [ -z "$BACKEND_REPO_URL" ]; then
    echo "URL repository backend wajib diisi."
    exit 1
  fi
  git clone "$BACKEND_REPO_URL" "$BACKEND_DIR"
else
  echo "Memperbarui repository backend..."
  cd "$BACKEND_DIR"
  git pull
fi

echo "Konfigurasi koneksi database dan Redis untuk worker."
read -p "DB host: " DB_HOST
read -p "DB port (default 5432): " DB_PORT
DB_PORT=${DB_PORT:-5432}
read -p "DB name: " DB_NAME
read -p "DB user: " DB_USER
read -s -p "DB password: " DB_PASS
echo ""
read -p "Redis host: " REDIS_HOST
read -p "Redis port (default 6379): " REDIS_PORT
REDIS_PORT=${REDIS_PORT:-6379}
read -s -p "Redis password (kosongkan jika tidak ada): " REDIS_PASS
echo ""

echo "Menyiapkan environment worker..."
cd "$BACKEND_DIR"

if [ ! -f ".env" ] && [ -f ".env.example" ]; then
  cp .env.example .env
fi

if [ -f ".env" ]; then
  CONNECTION_STRING="postgresql://$DB_USER:$DB_PASS@$DB_HOST:$DB_PORT/$DB_NAME?schema=public"
  if grep -q "^DATABASE_URL=" .env; then
    sed -i "s|^DATABASE_URL=.*|DATABASE_URL=\"$CONNECTION_STRING\"|" .env
  else
    printf "\nDATABASE_URL=\"%s\"\n" "$CONNECTION_STRING" >> .env
  fi

  if [ -z "$REDIS_PASS" ]; then
    REDIS_URL="redis://$REDIS_HOST:$REDIS_PORT"
  else
    REDIS_URL="redis://:$REDIS_PASS@$REDIS_HOST:$REDIS_PORT"
  fi

  if grep -q "^REDIS_URL=" .env; then
    sed -i "s|^REDIS_URL=.*|REDIS_URL=\"$REDIS_URL\"|" .env
  else
    printf "\nREDIS_URL=\"%s\"\n" "$REDIS_URL" >> .env
  fi
fi

npm install
npx prisma generate

if pm2 list | grep -q "absenta-worker"; then
  pm2 delete absenta-worker
fi

pm2 start "npm run worker" --name absenta-worker
pm2 save

echo "Worker server siap dengan proses queue berjalan."

