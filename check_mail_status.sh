#!/bin/bash
set -e

MAILCOW_DIR="/opt/mailcow-dockerized"

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

echo "=== Status Layanan Mail Server ==="

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

echo "--- Container Status ---"
$COMPOSE_CMD ps

echo ""
echo "--- Resource Usage ---"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"

echo ""
echo "--- Disk Usage ---"
df -h "$MAILCOW_DIR"

echo ""
echo "--- Postfix Queue ---"
# Cek antrian email di container postfix-mailcow
if docker ps | grep -q postfix-mailcow; then
  docker exec $(docker ps -qf name=postfix-mailcow) mailq
else
  echo "Container postfix-mailcow tidak berjalan."
fi
