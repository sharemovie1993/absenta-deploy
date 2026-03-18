#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

echo "=== ABSENTA PRE-DEPLOY PREPARE & CHECK ==="
echo "Skrip ini akan memastikan server Bapak siap 100% untuk deploy."
echo ""

# 1. Cek Ketersediaan Tool Dasar
echo "--> 1. Memeriksa Tool Sistem..."
need_cmd kubectl
need_cmd docker
need_cmd git
need_cmd nc
echo "   OK: Semua tool tersedia."

# 2. Cek File Konfigurasi (.env)
echo "--> 2. Memeriksa File Konfigurasi (.env)..."
load_env_files

check_var() {
  local var_name="$1"
  local val="${!var_name:-}"
  if [ -z "$val" ] || [[ "$val" == *"your-super-secret"* ]] || [[ "$val" == *"change-me"* ]]; then
    echo "   [!] PERINGATAN: $var_name belum diisi atau masih nilai default!"
    return 1
  fi
  return 0
}

ERR_COUNT=0
check_var "DATABASE_URL" || ERR_COUNT=$((ERR_COUNT+1))
check_var "REDIS_URL" || ERR_COUNT=$((ERR_COUNT+1))
check_var "JWT_SECRET" || ERR_COUNT=$((ERR_COUNT+1))
check_var "PUBLIC_APP_URL" || ERR_COUNT=$((ERR_COUNT+1))

if [ $ERR_COUNT -gt 0 ]; then
  echo "   Gagal: Ada $ERR_COUNT variabel kritis yang belum benar. Silakan cek folder env/ Bapak."
else
  echo "   OK: Variabel kritis sudah terisi."
fi

# 3. Cek Koneksi Database (Postgres)
echo "--> 3. Mengetes Koneksi Database (WireGuard)..."
# Ambil host dan port dari DATABASE_URL
DB_HOST=$(echo "$DATABASE_URL" | sed -e 's|.*@||' -e 's|:.*||' -e 's|/.*||')
DB_PORT=$(echo "$DATABASE_URL" | sed -e 's|.*:||' -e 's|/.*||')
if nc -z -w 5 "$DB_HOST" "$DB_PORT" 2>/dev/null; then
  echo "   OK: Terhubung ke Database di $DB_HOST:$DB_PORT"
else
  echo "   [!] GAGAL: Tidak bisa menjangkau Database di $DB_HOST:$DB_PORT. Cek VPN WireGuard Bapak!"
  ERR_COUNT=$((ERR_COUNT+1))
fi

# 4. Cek Koneksi Redis
echo "--> 4. Mengetes Koneksi Redis (WireGuard)..."
REDIS_HOST=$(echo "$REDIS_URL" | sed -e 's|redis://||' -e 's|:.*||')
REDIS_PORT=$(echo "$REDIS_URL" | sed -e 's|.*:||')
if nc -z -w 5 "$REDIS_HOST" "$REDIS_PORT" 2>/dev/null; then
  echo "   OK: Terhubung ke Redis di $REDIS_HOST:$REDIS_PORT"
else
  echo "   [!] GAGAL: Tidak bisa menjangkau Redis di $REDIS_HOST:$REDIS_PORT. Cek VPN WireGuard Bapak!"
  ERR_COUNT=$((ERR_COUNT+1))
fi

# 5. Cek Interface WireGuard (Penting untuk Binding K3s)
echo "--> 5. Memeriksa Interface WireGuard..."
WG_INTERFACE="${WG_INTERFACE:-wg0}"
WG_IP=$(ip -4 addr show "$WG_INTERFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "")
if [ -n "$WG_IP" ]; then
  echo "   OK: Ditemukan IP $WG_IP pada interface $WG_INTERFACE"
else
  echo "   [!] PERINGATAN: Interface $WG_INTERFACE tidak ditemukan! K3s mungkin tidak bisa diakses dari Reverse Proxy via WireGuard."
  ERR_COUNT=$((ERR_COUNT+1))
fi

echo ""
echo "=== HASIL PENGECEKAN ==="
if [ $ERR_COUNT -eq 0 ]; then
  echo "SANGAT BAGUS! Server Bapak sudah siap 100% untuk Live."
  echo ""
  echo "Panduan Langkah Selanjutnya (Ikuti ini agar sukses):"
  echo "1. Pastikan Izin Database sudah diperbaiki:"
  echo "   -> Masuk ke Menu Toolbox -> PostgreSQL Menu -> Pilih nomor 7 (Fix Permissions)."
  echo "2. Jalankan Menu 3 (Build Images) -> WAJIB agar Kubernetes punya paket aplikasi terbaru."
  echo "3. Jalankan Menu 4 (Deploy/Update) -> Untuk memasang aplikasi ke server."
  echo "4. Jalankan Menu 5 (Migration & Seed) -> Untuk menyiapkan struktur database."
  echo "5. Cek Menu 6 (Status) -> Semua harus 'Running' hijau."
else
  echo "Bapak masih punya $ERR_COUNT masalah yang harus diperbaiki (lihat tanda [!] di atas)."
  echo "Jangan deploy dulu ya Pak, perbaiki dulu masalah koneksi atau konfigurasinya."
fi
echo "========================"
