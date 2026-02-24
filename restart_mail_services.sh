#!/bin/bash
set -e

MAILCOW_DIR="/opt/mailcow-dockerized"

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

echo "=== Restart Layanan Mail Server ==="

if [ ! -d "$MAILCOW_DIR" ]; then
  echo "Error: Direktori Mailcow tidak ditemukan di $MAILCOW_DIR"
  exit 1
fi

cd "$MAILCOW_DIR"

echo "Mendeteksi perintah docker compose..."
COMPOSE_CMD=""
if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
else
  echo "Error: docker compose tidak ditemukan."
  exit 1
fi

echo "Restarting Mailcow containers..."
$COMPOSE_CMD down
echo "Menunggu 5 detik..."
sleep 5
$COMPOSE_CMD up -d

echo "Layanan berhasil direstart."
$COMPOSE_CMD ps
