#!/bin/bash
set -e

APP_ROOT="/var/www/absenta"
BACKEND_DIR="$APP_ROOT/backend"
FRONTEND_DIR="$APP_ROOT/frontend"
DB_NAME="absensi"
DB_USER="absensi_user"
DB_PASS="absensi_password_secure"

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root (sudo)."
  exit 1
fi

echo "Memperbarui paket sistem..."
apt update -y
apt upgrade -y

echo "Menginstall paket dasar..."
apt install -y curl git build-essential nginx ufw

echo "Memeriksa Node.js 18..."
if ! command -v node >/dev/null 2>&1; then
  curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
  apt install -y nodejs
fi

echo "Menginstall PM2 dan serve..."
if ! command -v pm2 >/dev/null 2>&1; then
  npm install -g pm2
fi
if ! command -v serve >/dev/null 2>&1; then
  npm install -g serve
fi

echo "Menginstall PostgreSQL dan Redis..."
apt install -y postgresql postgresql-contrib redis-server

systemctl enable postgresql
systemctl start postgresql
systemctl enable redis-server
systemctl start redis-server

echo "Menyiapkan database PostgreSQL..."
if ! sudo -u postgres psql -tAc "\du" | cut -d"|" -f1 | grep -qw "$DB_USER"; then
  sudo -u postgres psql -c "CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';"
fi
if ! sudo -u postgres psql -lqt | cut -d"|" -f1 | grep -qw "$DB_NAME"; then
  sudo -u postgres psql -c "CREATE DATABASE $DB_NAME OWNER $DB_USER;"
  sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
fi

echo "Mengkonfigurasi firewall UFW..."
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable

echo "Menyiapkan direktori aplikasi..."
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

echo "Menyiapkan backend..."
cd "$BACKEND_DIR"
if [ ! -f ".env" ] && [ -f ".env.example" ]; then
  cp .env.example .env
fi
if [ -f ".env" ]; then
  CONNECTION_STRING="postgresql://$DB_USER:$DB_PASS@localhost:5432/$DB_NAME?schema=public"
  if grep -q "^DATABASE_URL=" .env; then
    sed -i "s|^DATABASE_URL=.*|DATABASE_URL=\"$CONNECTION_STRING\"|" .env
  else
    printf "\nDATABASE_URL=\"%s\"\n" "$CONNECTION_STRING" >> .env
  fi
fi

if [ -x "./deploy_node18.sh" ] && [ -x "./deploy_all.sh" ]; then
  ./deploy_node18.sh
  ./deploy_all.sh
else
  npm install
  npx prisma generate
  npx prisma migrate deploy
  npm run build
  if pm2 list | grep -q "absenta-backend"; then
    pm2 reload absenta-backend
  else
    pm2 start dist/main.js --name absenta-backend --node-args "-r tsconfig-paths/register"
  fi
  pm2 save
fi

echo "Menyiapkan frontend..."
cd "$FRONTEND_DIR"
if [ -x "./deploy_frontend.sh" ]; then
  ./deploy_frontend.sh
else
  npm install
  npm run build
  if pm2 list | grep -q "absenta-frontend"; then
    pm2 reload absenta-frontend
  else
    pm2 start "serve -s dist -l 8080" --name absenta-frontend
  fi
  pm2 save
fi

echo "Deploy backend dan frontend selesai."
