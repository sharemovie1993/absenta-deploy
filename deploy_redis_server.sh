#!/bin/bash
set -e

REDIS_PASSWORD="${REDIS_PASSWORD:-}"

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

echo "Memperbarui paket sistem..."
apt update -y
apt upgrade -y

echo "Menginstall Redis Server..."
apt install -y redis-server

echo "Mengaktifkan service Redis..."
systemctl enable redis-server
systemctl start redis-server

if [ -n "$REDIS_PASSWORD" ]; then
  echo "Mengkonfigurasi password Redis..."
  CONF_FILE="/etc/redis/redis.conf"
  if grep -q "^#\?requirepass" "$CONF_FILE"; then
    sed -i "s/^#\?requirepass.*/requirepass $REDIS_PASSWORD/" "$CONF_FILE"
  else
    printf "\nrequirepass %s\n" "$REDIS_PASSWORD" >> "$CONF_FILE"
  fi
  systemctl restart redis-server
fi

echo "Redis Server siap dijalankan."

