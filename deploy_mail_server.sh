#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

echo "=== Deploy Mail Server dengan GUI (Mailcow Dockerized) ==="
echo "Script ini akan:"
echo "- Menginstall docker (jika belum ada)"
echo "- Menginstall docker compose (plugin atau docker-compose) jika belum ada"
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

echo "Menginstall dependensi docker dan git..."
apt-get install -y docker.io git

echo "Mengaktifkan dan memulai service docker..."
systemctl enable docker
systemctl start docker

echo "Mendeteksi perintah docker compose / docker-compose..."
COMPOSE_CMD=""
if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
else
  echo "docker compose / docker-compose belum terpasang, mencoba menginstall docker-compose-plugin..."
  if apt-get install -y docker-compose-plugin; then
    if docker compose version >/dev/null 2>&1; then
      COMPOSE_CMD="docker compose"
    fi
  fi
fi

if [ -z "$COMPOSE_CMD" ]; then
  echo "Gagal menemukan docker compose atau docker-compose."
  echo "Silakan pastikan paket docker-compose-plugin atau docker-compose terinstal secara manual."
  exit 1
fi

echo "Menggunakan perintah: $COMPOSE_CMD"

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
echo "=== Menjalankan mail server ($COMPOSE_CMD up -d) ==="
read -p "Jalankan '$COMPOSE_CMD up -d' untuk menghidupkan semua layanan mail server? (y/n): " RUN_MAIL
if [ "$RUN_MAIL" = "y" ]; then
  $COMPOSE_CMD pull
  $COMPOSE_CMD up -d
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
echo "=== Langkah berikutnya di UI Mailcow ==="
echo "1. Buka URL panel di atas di browser."
echo "2. Login menggunakan kredensial default:"
echo "   - Username: admin"
echo "   - Password: moohoo"
echo "3. Setelah login pertama, segera ubah password admin untuk keamanan."
echo "4. Tambahkan domain pengirim email Anda di menu Configuration -> Mail setup."
echo "5. Buat mailbox baru (misalnya no-reply@domain-anda) di tab Mailboxes."
echo "6. Catat alamat email, username, dan password mailbox tersebut untuk konfigurasi SMTP di aplikasi Absenta."
echo ""
echo "Deploy mail server selesai. Mail server siap diakses dan dikonfigurasi melalui UI."
