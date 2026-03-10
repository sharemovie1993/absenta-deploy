#!/bin/bash
set -e

# Script ini dijalankan DI DALAM server mail (10.50.0.4)
# Fungsinya untuk memastikan konfigurasi internal mailcow benar

MAILCOW_DIR="/opt/mailcow-dockerized"

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

echo "=== Konfigurasi Internal Mail Server (Mailcow) ==="

if [ ! -d "$MAILCOW_DIR" ]; then
  echo "Error: Direktori Mailcow tidak ditemukan di $MAILCOW_DIR"
  echo "Pastikan Anda menjalankan script ini di server yang sudah terinstall Mailcow."
  exit 1
fi

cd "$MAILCOW_DIR"

echo "Memeriksa konfigurasi mailcow.conf..."
if grep -q "HTTP_BIND=127.0.0.1" mailcow.conf; then
  echo "WARNING: HTTP_BIND diset ke 127.0.0.1. Ini akan mencegah akses dari VPS (Reverse Proxy)."
  echo "Mengubah HTTP_BIND ke 0.0.0.0..."
  sed -i 's/HTTP_BIND=127.0.0.1/HTTP_BIND=0.0.0.0/g' mailcow.conf
fi

if grep -q "HTTPS_BIND=127.0.0.1" mailcow.conf; then
  echo "WARNING: HTTPS_BIND diset ke 127.0.0.1. Ini akan mencegah akses dari VPS (Reverse Proxy)."
  echo "Mengubah HTTPS_BIND ke 0.0.0.0..."
  sed -i 's/HTTPS_BIND=127.0.0.1/HTTPS_BIND=0.0.0.0/g' mailcow.conf
fi

# Pastikan port standar terbuka di firewall internal (jika ada)
echo "Memastikan port mail terbuka di iptables/UFW..."
PORTS="25 80 443 110 143 465 587 993 995"

if command -v ufw >/dev/null 2>&1; then
  if ufw status | grep -q "Active"; then
    echo "UFW aktif. Membuka port..."
    for PORT in $PORTS; do
      ufw allow $PORT/tcp
    done
    ufw reload
  else
    echo "UFW tidak aktif (OK)."
  fi
fi

# Cek apakah docker-compose.override.yml ada, jika tidak buat default
if [ ! -f "docker-compose.override.yml" ]; then
  echo "Membuat docker-compose.override.yml kosong (aman)..."
  cat > docker-compose.override.yml <<EOF
version: '2.1'
services:
  ipv6nat-mailcow:
    image: bash:latest
    restart: "no"
    entrypoint: ["echo", "IPv6 NAT disabled"]
EOF
fi

echo "Konfigurasi internal selesai."
echo "Jalankan 'Restart Layanan' untuk menerapkan perubahan jika ada."
