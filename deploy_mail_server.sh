#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

echo "=== Deploy Mail Server dengan GUI (Mailcow Dockerized) ==="
echo "Script ini akan:"
echo "- Menginstall docker dan docker compose plugin (jika belum ada)"
echo "- Menginstall git"
echo "- Meng-clone mailcow/mailcow-dockerized ke /opt/mailcow-dockerized"
echo ""
read -p "Lanjutkan? (y/n): " CONT
if [ "$CONT" != "y" ]; then
  echo "Batal."
  exit 0
fi

echo "Memperbarui package index..."
apt-get update -y

echo "Menginstall dependensi docker, docker-compose-plugin, git..."
apt-get install -y docker.io docker-compose-plugin git

echo "Mengaktifkan dan memulai service docker..."
systemctl enable docker
systemctl start docker

MAILCOW_DIR="/opt/mailcow-dockerized"

if [ -d "$MAILCOW_DIR" ]; then
  echo "Direktori $MAILCOW_DIR sudah ada."
  read -p "Overwrite / update repo mailcow di direktori ini? (y/n): " OVERWRITE
  if [ "$OVERWRITE" != "y" ]; then
    echo "Batal mengubah instalasi mail server."
    exit 0
  fi
  cd "$MAILCOW_DIR"
  echo "Menarik update terbaru dari repo mailcow..."
  git pull --ff-only || true
else
  echo "Meng-clone mailcow/mailcow-dockerized ke $MAILCOW_DIR ..."
  git clone https://github.com/mailcow/mailcow-dockerized.git "$MAILCOW_DIR"
  cd "$MAILCOW_DIR"
fi

echo ""
echo "=== Konfigurasi Mailcow ==="
echo "Mailcow membutuhkan konfigurasi domain, hostname, dan opsi lain."
echo "Script ini akan memanggil ./generate_config.sh (interactive)."
echo "Jika sebelumnya sudah pernah dikonfigurasi, Anda bisa melewati dengan Ctrl+C."
echo ""
read -p "Jalankan ./generate_config.sh sekarang? (y/n): " GENCONF
if [ "$GENCONF" = "y" ]; then
  ./generate_config.sh
fi

echo ""
echo "=== Menjalankan mail server (docker compose up -d) ==="
read -p "Jalankan 'docker compose up -d' untuk menghidupkan semua layanan mail server? (y/n): " RUN_MAIL
if [ "$RUN_MAIL" = "y" ]; then
  docker compose pull
  docker compose up -d
fi

echo ""
echo "Mail server (Mailcow) telah dipersiapkan."
echo "Panel administrasi biasanya dapat diakses di:"
echo "- https://mail.<domain_anda> atau https://<hostname_yang_dikonfigurasi>"
echo ""
echo "Pastikan:"
echo "- DNS MX, A, dan SPF/DMARC sudah di-set di provider domain"
echo "- Port 25, 80, 443, 587, 993 dibuka di firewall/VPS provider"
echo ""
echo "Deploy mail server selesai (tahap dasar)."

