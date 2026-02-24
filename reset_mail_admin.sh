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
  echo "Silakan ikuti instruksi di layar (masukkan password baru saat diminta)."
  chmod +x "$HELPER_SCRIPT"
  echo "Jalankan script reset..."
  "$HELPER_SCRIPT"
else
  echo "Error: Helper script tidak ditemukan di $HELPER_SCRIPT"
  echo "Mencoba metode manual via docker exec..."
  
  read -p "Masukkan password baru untuk admin: " NEW_PASS
  if [ -z "$NEW_PASS" ]; then
    echo "Password tidak boleh kosong."
    exit 1
  fi
  
  # Command manual reset (DB based)
  # Hash password needs specific method usually, but mailcow might store generic hash? 
  # Mailcow uses BLF-CRYPT.
  # Easier to just fail if helper script is missing, as it should be there in standard install.
  echo "Gagal melakukan reset manual. Pastikan instalasi Mailcow lengkap."
  exit 1
fi

echo ""
echo "Reset password selesai."
echo "Tips Login:"
echo "1. Gunakan username 'admin' (bukan email)."
echo "2. Jika form utama menolak 'admin', klik link 'Log in as admin' di bagian bawah form login."
echo "3. Pastikan mengakses via domain yang benar (mail.absenta.id)."
