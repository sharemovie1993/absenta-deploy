#!/bin/bash
set -e

APP_ROOT="${APP_ROOT:-/var/www/absenta}"
BACKEND_DIR="$APP_ROOT/backend"
FRONTEND_DIR="$APP_ROOT/frontend"

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

echo "Memperbarui paket sistem..."
apt update -y
apt upgrade -y

echo "Menginstall paket dasar..."
apt install -y curl git build-essential nginx postgresql-client redis-tools

NODE_VERSION_MAJOR="${NODE_VERSION_MAJOR:-24}"
echo "Memeriksa Node.js ${NODE_VERSION_MAJOR}.x..."
if command -v node >/dev/null 2>&1; then
  CURRENT_NODE="$(node -v 2>/dev/null | sed 's/^v//')"
  CURRENT_MAJOR="$(printf "%s" "$CURRENT_NODE" | cut -d. -f1)"
  if [ "$CURRENT_MAJOR" != "$NODE_VERSION_MAJOR" ]; then
    echo "Versi Node saat ini $CURRENT_NODE, menginstall Node ${NODE_VERSION_MAJOR}.x..."
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION_MAJOR}.x" | bash -
    apt install -y nodejs
  else
    echo "Node.js sudah versi ${NODE_VERSION_MAJOR}.x"
  fi
else
  echo "Node.js belum terpasang, menginstall Node ${NODE_VERSION_MAJOR}.x..."
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION_MAJOR}.x" | bash -
  apt install -y nodejs
fi

echo "Menginstall PM2 dan serve..."
if ! command -v pm2 >/dev/null 2>&1; then
  npm install -g pm2
fi
if ! command -v serve >/dev/null 2>&1; then
  npm install -g serve
fi

echo "Mengkonfigurasi PM2 agar auto-start saat reboot..."
pm2 startup systemd -u root --hp /root || true

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

if [ ! -d "$FRONTEND_DIR/.git" ]; then
  echo "Repository frontend belum ada."
  read -p "Masukkan URL repository frontend (https): " FRONTEND_REPO_URL
  if [ -z "$FRONTEND_REPO_URL" ]; then
    echo "URL repository frontend wajib diisi."
    exit 1
  fi
  git clone "$FRONTEND_REPO_URL" "$FRONTEND_DIR"
else
  echo "Memperbarui repository frontend..."
  cd "$FRONTEND_DIR"
  git pull
fi

echo "Konfigurasi koneksi database dan Redis untuk backend."
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

echo "Menyiapkan backend..."
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
npx prisma migrate deploy
npx prisma db seed || true
if command -v npx >/dev/null 2>&1; then
  npx ts-node -r tsconfig-paths/register prisma/seed.ts || echo "Seed prisma/seed.ts gagal (lanjutkan proses)"
fi
npm run build

if pm2 list | grep -q "absenta-backend"; then
  pm2 reload absenta-backend
else
  pm2 start dist/main.js --name absenta-backend --node-args "-r tsconfig-paths/register"
fi
pm2 save

echo "Menyiapkan frontend..."
cd "$FRONTEND_DIR"
npm install
npm run build

if pm2 list | grep -q "absenta-frontend"; then
  pm2 reload absenta-frontend
else
  pm2 start "serve -s dist -l 8080" --name absenta-frontend
fi
pm2 save

echo "App server siap dengan backend dan frontend berjalan."
echo ""
echo "Catatan: Setelah deploy pertama kali, jalankan seed data awal:"
echo "  - Via menu ABSENTA: Deploy -> PostgreSQL -> 3.12 Seed data awal (Prisma db seed)"
echo "  - Atau manual: cd \"$BACKEND_DIR\" && npx prisma db seed"
