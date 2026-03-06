#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

INSTALL_DIR_DEFAULT="/var/www/cbt"
read -p "Direktori instalasi (default $INSTALL_DIR_DEFAULT): " INSTALL_DIR
INSTALL_DIR=${INSTALL_DIR:-$INSTALL_DIR_DEFAULT}
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

EXISTING_BIN="$(find "$INSTALL_DIR" -type f \( -name 'main-amd64' -o -name 'main-arm64' \) | head -n1)"
if [ -n "$EXISTING_BIN" ]; then
  read -p "Binary EXO terdeteksi di $(dirname "$EXISTING_BIN"). Lewati unduh/ekstrak? (y/n, default y): " SKIP_DL
  SKIP_DL=${SKIP_DL:-y}
else
  SKIP_DL="n"
fi

if ! command -v wget >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y wget
  elif command -v apt >/dev/null 2>&1; then
    apt update -y
    apt install -y wget
  fi
fi
if ! command -v unzip >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y unzip
  elif command -v apt >/dev/null 2>&1; then
    apt update -y
    apt install -y unzip
  fi
fi

if [ "$SKIP_DL" = "n" ] || [ "$SKIP_DL" = "N" ]; then
  URL_DEFAULT="https://s3.ekstraordinary.com/extraordinarycbt/release-rosetta/4.6.3-linux+1.zip"
  read -p "URL paket CBT EXO (default $URL_DEFAULT): " PKG_URL
  PKG_URL=${PKG_URL:-$URL_DEFAULT}
  PKG_NAME="$(basename "$PKG_URL")"
  echo "Mengunduh paket: $PKG_URL"
  wget -O "$PKG_NAME" "$PKG_URL"

  if echo "$PKG_NAME" | grep -qi '\.zip$'; then
    unzip -o "$PKG_NAME"
  elif echo "$PKG_NAME" | grep -qi '\.tar\.gz$'; then
    tar -xzf "$PKG_NAME"
  fi
fi

ARCH="$(uname -m)"
FOUND_PATH="$(find "$INSTALL_DIR" -type f \( -name 'main-amd64' -o -name 'main-arm64' \) | head -n1)"
if [ -z "$FOUND_PATH" ]; then
  echo "Binary aplikasi tidak ditemukan."
  exit 1
fi
APP_ROOT="$(dirname "$FOUND_PATH")"
BIN_FILE="$(basename "$FOUND_PATH")"
chmod +x "$FOUND_PATH"

if ! command -v psql >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y
    apt-get install -y postgresql postgresql-contrib
  elif command -v apt >/dev/null 2>&1; then
    apt update -y
    apt install -y postgresql postgresql-contrib
  fi
fi

DB_USER_DEFAULT="cbt_user"
DB_NAME_DEFAULT="cbt_db"
DB_HOST_DEFAULT="localhost"
DB_PORT_DEFAULT="5432"
read -p "Nama user database (default $DB_USER_DEFAULT): " DB_USER
DB_USER=${DB_USER:-$DB_USER_DEFAULT}
read -s -p "Password database untuk $DB_USER: " DB_PASS
echo ""
read -p "Nama database (default $DB_NAME_DEFAULT): " DB_NAME
DB_NAME=${DB_NAME:-$DB_NAME_DEFAULT}
DB_HOST=${DB_HOST_DEFAULT}
DB_PORT=${DB_PORT_DEFAULT}

EXIST_USER=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$DB_USER';" 2>/dev/null || true)
if [ "$EXIST_USER" != "1" ]; then
  ESCAPED=${DB_PASS//\'/\'\'}
  sudo -u postgres psql -c "CREATE USER \"$DB_USER\" WITH PASSWORD '$ESCAPED';"
else
  ESCAPED=${DB_PASS//\'/\'\'}
  sudo -u postgres psql -c "ALTER ROLE \"$DB_USER\" WITH PASSWORD '$ESCAPED';"
fi
EXIST_DB=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME';" 2>/dev/null || true)
if [ "$EXIST_DB" != "1" ]; then
  sudo -u postgres psql -c "CREATE DATABASE \"$DB_NAME\" OWNER \"$DB_USER\";"
fi
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE \"$DB_NAME\" TO \"$DB_USER\";"

SQL_FILE="$(find "$INSTALL_DIR" -type f -name 'exo-dump-master.sql' | head -n1)"
if [ -n "$SQL_FILE" ]; then
  SHOULD_IMPORT="y"
  EXISTS_TABLE=$(
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -tAc "SELECT to_regclass('public.pesertas') IS NOT NULL;" 2>/dev/null | tr -d '[:space:]'
  )
  if [ "$EXISTS_TABLE" = "t" ] || [ "$EXISTS_TABLE" = "true" ]; then
    read -p "Tabel terdeteksi di DB ($DB_NAME). Lewati import SQL? (y/n, default y): " SKIP_SQL
    SKIP_SQL=${SKIP_SQL:-y}
    if [ "$SKIP_SQL" = "y" ] || [ "$SKIP_SQL" = "Y" ]; then
      SHOULD_IMPORT="n"
    fi
  fi
  if [ "$SHOULD_IMPORT" = "y" ] || [ "$SHOULD_IMPORT" = "Y" ]; then
    echo "Import data SQL..."
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$SQL_FILE" || true
  else
    echo "Melewati import SQL."
  fi
fi

UPDATER_SQL="$(find "$INSTALL_DIR" -type f -name 'update_dari_4.5.0_execute_ini.sql' | head -n1)"
if [ -n "$UPDATER_SQL" ]; then
  read -p "Temukan skrip update (update_dari_4.5.0_execute_ini.sql). Jalankan sekarang? (y/n, default n): " RUN_UPD
  RUN_UPD=${RUN_UPD:-n}
  if [ "$RUN_UPD" = "y" ] || [ "$RUN_UPD" = "Y" ]; then
    echo "Menjalankan skrip update..."
    PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$UPDATER_SQL" || true
  fi
fi

mkdir -p "$APP_ROOT/storage"
chmod -R 775 "$APP_ROOT/storage"

ENV_FILE="$APP_ROOT/.env"
read -p "License key CBT EXO: " LICENSE_KEY
if [ -f "$ENV_FILE" ]; then
  read -p ".env sudah ada. Overwrite (o), Merge/Update (m), Skip (s)? (default m): " ENV_ACT
  ENV_ACT=${ENV_ACT:-m}
  case "$ENV_ACT" in
    o|O)
      TS="$(date +%Y%m%d%H%M%S)"
      cp "$ENV_FILE" "${ENV_FILE}.bak_$TS" || true
      cat > "$ENV_FILE" <<EOF
SERVER_SECRET_LICENSE_KEY=$LICENSE_KEY
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
STORAGE_PATH=$APP_ROOT/storage
EOF
      ;;
    s|S)
      :
      ;;
    *)
      TMP_ENV="$(mktemp)"
      cat > "$TMP_ENV" <<EOF
SERVER_SECRET_LICENSE_KEY=$LICENSE_KEY
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
STORAGE_PATH=$APP_ROOT/storage
EOF
      for k in SERVER_SECRET_LICENSE_KEY DB_NAME DB_USER DB_PASS DB_HOST DB_PORT STORAGE_PATH; do
        V="$(grep -E "^$k=" "$TMP_ENV" | head -n1)"
        if grep -qE "^$k=" "$ENV_FILE"; then
          sed -i "s|^$k=.*|$V|g" "$ENV_FILE"
        else
          printf "%s\n" "$V" >> "$ENV_FILE"
        fi
      done
      rm -f "$TMP_ENV"
      ;;
  esac
else
  cat > "$ENV_FILE" <<EOF
SERVER_SECRET_LICENSE_KEY=$LICENSE_KEY
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS
DB_HOST=$DB_HOST
DB_PORT=$DB_PORT
STORAGE_PATH=$APP_ROOT/storage
EOF
fi

read -p "Buka firewall port 9988/tcp untuk akses CBT? (y/n, default y): " OPEN_FW
OPEN_FW=${OPEN_FW:-y}
if [ "$OPEN_FW" = "y" ] || [ "$OPEN_FW" = "Y" ]; then
  if command -v ufw >/dev/null 2>&1; then
    ufw allow 9988/tcp || true
  elif command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent --add-port=9988/tcp || true
    firewall-cmd --reload || true
  elif command -v iptables >/dev/null 2>&1; then
    iptables -C INPUT -p tcp --dport 9988 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 9988 -j ACCEPT || true
    if command -v netfilter-persistent >/dev/null 2>&1; then
      netfilter-persistent save || true
    elif command -v service >/dev/null 2>&1 && [ -x /etc/init.d/netfilter-persistent ]; then
      service netfilter-persistent save || true
    elif [ -x /sbin/iptables-save ] && [ -d /etc/iptables ]; then
      /sbin/iptables-save > /etc/iptables/rules.v4 || true
    fi
  else
    echo "Tidak menemukan tool firewall standar (ufw/firewall-cmd/iptables). Lewati konfigurasi firewall."
  fi
fi

read -p "Buat service systemd agar aplikasi berjalan otomatis? (y/n, default y): " MAKE_SVC
MAKE_SVC=${MAKE_SVC:-y}
if [ "$MAKE_SVC" = "y" ] || [ "$MAKE_SVC" = "Y" ]; then
  if command -v ss >/dev/null 2>&1 && ss -plnt 2>/dev/null | grep -q ":9988 "; then
    echo "Terdapat proses yang menggunakan port 9988."
    read -p "Hentikan proses yang menggunakan 9988 sebelum start service? (y/n, default y): " KILL9988
    KILL9988=${KILL9988:-y}
    if [ "$KILL9988" = "y" ] || [ "$KILL9988" = "Y" ]; then
      if command -v fuser >/dev/null 2>&1; then
        fuser -k 9988/tcp || true
      fi
    fi
  fi
  SVC_PATH="/etc/systemd/system/cbt-exo.service"
  cat > "$SVC_PATH" <<EOF
[Unit]
Description=CBT EXO Service
After=network.target postgresql.service

[Service]
Type=simple
WorkingDirectory=$APP_ROOT
EnvironmentFile=$ENV_FILE
ExecStart=$APP_ROOT/$BIN_FILE
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable cbt-exo.service
  systemctl restart cbt-exo.service || true
  systemctl status cbt-exo.service --no-pager -l | head -n 20 || true
else
  echo "Jalankan aplikasi secara manual dengan:"
  echo "$INSTALL_DIR/$BIN_FILE"
fi

echo "Deploy CBT EXO selesai."
