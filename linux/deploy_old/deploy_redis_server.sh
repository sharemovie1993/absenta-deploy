#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

read -p "Masukkan password Redis (kosongkan jika tanpa password): " REDIS_PASSWORD_INPUT
REDIS_PASSWORD="${REDIS_PASSWORD_INPUT:-$REDIS_PASSWORD}"

echo "Memperbarui paket sistem..."
apt update -y
apt upgrade -y

echo "Menginstall Redis Server..."
# Prefer official Redis packages (>=6.2) for Debian/Ubuntu
if ! command -v lsb_release >/dev/null 2>&1; then
  apt install -y lsb-release
fi
apt install -y curl gpg
CODENAME="$(lsb_release -cs 2>/dev/null || echo "stable")"
if [ ! -f "/usr/share/keyrings/redis-archive-keyring.gpg" ]; then
  curl -fsSL https://packages.redis.io/gpg | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
fi
if ! grep -q "packages.redis.io" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
  echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb ${CODENAME} main" > /etc/apt/sources.list.d/redis.list
fi
apt update -y
apt install -y redis-server

echo "Mengaktifkan service Redis..."
systemctl enable redis-server
systemctl start redis-server

CONF_FILE="/etc/redis/redis.conf"

# Ensure supervised mode for systemd
if grep -q "^supervised " "$CONF_FILE"; then
  sed -i "s/^supervised .*/supervised systemd/" "$CONF_FILE"
else
  printf "\nsupervised systemd\n" >> "$CONF_FILE"
fi

echo "Konfigurasi bind address Redis:"
echo "1) Hanya localhost (127.0.0.1) [aman untuk single server]"
echo "2) Localhost + IP ini (misal IP WireGuard)"
echo "3) Semua interface (0.0.0.0) [gunakan hanya jika firewall ketat]"
read -p "Pilih opsi bind [1/2/3] (default 1): " BIND_CHOICE
if [ -z "$BIND_CHOICE" ]; then
  BIND_CHOICE=1
fi

SERVER_IP=$(hostname -I | awk '{print $1}')

if grep -q "^bind " "$CONF_FILE"; then
  sed -i "s/^bind .*/bind 127.0.0.1/" "$CONF_FILE"
else
  printf "\nbind 127.0.0.1\n" >> "$CONF_FILE"
fi

if [ "$BIND_CHOICE" = "2" ]; then
  read -p "Masukkan IP tambahan untuk bind (default $SERVER_IP): " EXTRA_IP
  if [ -z "$EXTRA_IP" ]; then
    EXTRA_IP="$SERVER_IP"
  fi
  sed -i "s/^bind .*/bind 127.0.0.1 $EXTRA_IP/" "$CONF_FILE"
elif [ "$BIND_CHOICE" = "3" ]; then
  sed -i "s/^bind .*/bind 0.0.0.0/" "$CONF_FILE"
fi

if [ -n "$REDIS_PASSWORD" ]; then
  echo "Mengkonfigurasi password Redis..."
  if grep -q "^#\?requirepass" "$CONF_FILE"; then
    sed -i "s/^#\?requirepass.*/requirepass $REDIS_PASSWORD/" "$CONF_FILE"
  else
    printf "\nrequirepass %s\n" "$REDIS_PASSWORD" >> "$CONF_FILE"
  fi
  systemctl restart redis-server
else
  systemctl restart redis-server
fi

echo "Redis Server siap dijalankan."

# Version check
REDIS_VER="$(redis-server -v 2>/dev/null | awk '{print $3}' | sed 's/=//;s/redis_version://')"
echo "Versi Redis terpasang: ${REDIS_VER}"
if printf "%s\n6.2.0\n${REDIS_VER}" | sort -V | head -n1 | grep -q "^${REDIS_VER}$"; then
  echo "Peringatan: versi Redis < 6.2 terdeteksi. Pertimbangkan upgrade distro/repo."
fi
