#!/bin/bash
set -e

# Script ini dijalankan DI DALAM server mail (10.50.0.4)
# Fungsinya untuk mereset password admin mailcow

MAILCOW_DIR="/opt/mailcow-dockerized"

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

echo "=== Reset Password Admin Mailcow ==="

if [ ! -d "$MAILCOW_DIR" ]; then
  echo "Error: Direktori Mailcow tidak ditemukan di $MAILCOW_DIR"
  echo "Pastikan Anda menjalankan script ini di server yang sudah terinstall Mailcow."
  exit 1
fi

cd "$MAILCOW_DIR"

HELPER_SCRIPT="./helper-scripts/reset_admin_password.sh"

if [ -f "$HELPER_SCRIPT" ]; then
  echo "Menjalankan script reset password bawaan Mailcow..."
  chmod +x "$HELPER_SCRIPT"
  "$HELPER_SCRIPT"
else
  echo "Warning: Helper script tidak ditemukan di $HELPER_SCRIPT"
  echo "Mencoba metode manual via docker exec (Database)..."
  
  # Load konfigurasi database
  if [ -f "mailcow.conf" ]; then
    source mailcow.conf
  else
    echo "Error: mailcow.conf tidak ditemukan."
    exit 1
  fi

  read -p "Masukkan password baru untuk admin: " NEW_PASS
  if [ -z "$NEW_PASS" ]; then
    echo "Password tidak boleh kosong."
    exit 1
  fi
  
  echo "Mencari container..."
  DOVECOT_CONTAINER=$(docker ps --format '{{.Names}}' | grep "dovecot-mailcow" | head -n 1)
  MYSQL_CONTAINER=$(docker ps --format '{{.Names}}' | grep "mysql-mailcow" | head -n 1)

  if [ -z "$DOVECOT_CONTAINER" ]; then
    echo "Error: Container dovecot-mailcow tidak ditemukan. Pastikan mail server berjalan (docker compose up -d)."
    exit 1
  fi

  if [ -z "$MYSQL_CONTAINER" ]; then
    echo "Error: Container mysql-mailcow tidak ditemukan. Pastikan mail server berjalan."
    exit 1
  fi

  echo "Generating password hash (BLF-CRYPT)..."
  # Menggunakan doveadm di dalam container dovecot untuk generate hash yang valid
  HASH=$(docker exec -i "$DOVECOT_CONTAINER" doveadm pw -s BLF-CRYPT -p "$NEW_PASS")
  
  if [ -z "$HASH" ]; then
    echo "Error: Gagal membuat hash password."
    exit 1
  fi
  
  # Bersihkan output hash jika ada warning (ambil string yang dimulai dengan {BLF-CRYPT})
  HASH=$(echo "$HASH" | grep -o '{BLF-CRYPT}.*')

  echo "Updating database..."
  # Update password user admin
  docker exec -i "$MYSQL_CONTAINER" mysql -u"${DBUSER}" -p"${DBPASS}" "${DBNAME}" -e "UPDATE admin SET password = '$HASH', active = '1' WHERE username = 'admin';"
  
  if [ $? -eq 0 ]; then
    echo "Password admin berhasil direset via Database!"
  else
    echo "Gagal mengupdate database."
    exit 1
  fi
fi

echo ""
echo "Reset password selesai."
echo "Tips Login:"
echo "1. Gunakan username 'admin' (bukan email)."
echo "2. Jika form utama menolak 'admin', klik link 'Log in as admin' di bagian bawah form login."
echo "3. Pastikan mengakses via domain yang benar (mail.absenta.id)."
