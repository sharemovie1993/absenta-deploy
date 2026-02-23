#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"
BACKUP_DIR="/etc/nginx/backup"

mkdir -p "$BACKUP_DIR"

read -p "Base domain utama (misal absenta.id): " BASE_DOMAIN

if [ -z "$BASE_DOMAIN" ]; then
  echo "Base domain wajib diisi."
  exit 1
fi

API_DOMAIN="api.${BASE_DOMAIN}"

echo "Mencari konfigurasi Nginx yang menggunakan domain:"
echo "- $API_DOMAIN"
echo "- $BASE_DOMAIN dan wildcard *.$BASE_DOMAIN"
echo ""

MATCH_FILES=$(grep -RIlE "server_name[[:space:]]+(${API_DOMAIN}|\\*\\.${BASE_DOMAIN}|${BASE_DOMAIN})" "$NGINX_SITES_AVAILABLE" "$NGINX_SITES_ENABLED" 2>/dev/null || true)

if [ -z "$MATCH_FILES" ]; then
  echo "Tidak ditemukan konfigurasi Nginx yang cocok dengan domain tersebut di sites-available/sites-enabled."
  exit 0
fi

CANONICAL_CONF="${NGINX_SITES_AVAILABLE}/absenta.conf"

echo "Ditemukan file konfigurasi berikut:"
INDEX=1
declare -a FILE_LIST
while IFS= read -r FILE; do
  FILE_LIST[$INDEX]="$FILE"
  if [ "$FILE" = "$CANONICAL_CONF" ]; then
    MARK=" (CANONICAL: absenta.conf yang dibuat script deploy_nginx_proxy.sh)"
  else
    MARK=""
  fi
  echo "[$INDEX] $FILE$MARK"
  INDEX=$((INDEX + 1))
done <<< "$MATCH_FILES"

echo ""
echo "Catatan:"
echo "- File CANONICAL ($CANONICAL_CONF) biasanya adalah konfigurasi terbaru dari script deploy_nginx_proxy.sh."
echo "- File lain yang menggunakan domain sama berpotensi menyebabkan konflik server_name."
echo ""

while true; do
  read -p "Pilih nomor file yang akan dibersihkan (0 untuk selesai): " CHOICE

  if [ "$CHOICE" = "0" ]; then
    echo "Selesai membersihkan konfigurasi Nginx lama."
    break
  fi

  if ! [[ "$CHOICE" =~ ^[0-9]+$ ]]; then
    echo "Input harus berupa angka."
    continue
  fi

  SELECTED="${FILE_LIST[$CHOICE]}"

  if [ -z "$SELECTED" ]; then
    echo "Nomor tidak valid."
    continue
  fi

  if [ "$SELECTED" = "$CANONICAL_CONF" ]; then
    echo "Peringatan: ini adalah file CANONICAL ($CANONICAL_CONF). Disarankan tidak dihapus."
    read -p "Tetap lanjut operasi pada file ini? (y/n, default n): " CONFIRM_CANON
    CONFIRM_CANON=${CONFIRM_CANON:-n}
    case "$CONFIRM_CANON" in
      y|Y) ;;
      *)
        echo "Melewati file CANONICAL."
        continue
        ;;
    esac
  fi

  echo ""
  echo "File terpilih: $SELECTED"

  if [ -L "$SELECTED" ]; then
    REAL_PATH="$(readlink -f "$SELECTED" || echo "")"
    if [ -n "$REAL_PATH" ]; then
      echo "Ini adalah symlink yang menunjuk ke: $REAL_PATH"
    fi
  fi

  echo "Pilih aksi:"
  echo "1) Backup + disable (pindah ke backup dan hapus dari sites-enabled)"
  echo "2) Backup saja (file disalin ke backup, tidak mengubah sites-enabled)"
  echo "3) Disable saja (hapus dari sites-enabled tanpa backup tambahan)"
  echo "4) Hapus permanen file ini"
  echo "0) Batal untuk file ini"
  read -p "Aksi: " ACTION

  TIMESTAMP=$(date +%Y%m%d%H%M%S)
  BASENAME=$(basename "$SELECTED")
  BACKUP_PATH="${BACKUP_DIR}/${BASENAME}.${TIMESTAMP}.bak"

  case "$ACTION" in
    1)
      echo "Membackup ke: $BACKUP_PATH"
      cp -a "$SELECTED" "$BACKUP_PATH"
      if [ "$SELECTED" = "$CANONICAL_CONF" ]; then
        echo "Hanya backup CANONICAL, tidak menghapus dari sites-enabled."
      else
        if [ "$SELECTED" = "${NGINX_SITES_ENABLED}/${BASENAME}" ] && [ -L "$SELECTED" ]; then
          rm -f "$SELECTED"
          echo "Symlink $SELECTED dihapus dari sites-enabled."
        fi
      fi
      ;;
    2)
      echo "Membackup ke: $BACKUP_PATH"
      cp -a "$SELECTED" "$BACKUP_PATH"
      ;;
    3)
      if [ "$SELECTED" = "${NGINX_SITES_ENABLED}/${BASENAME}" ] && [ -L "$SELECTED" ]; then
        rm -f "$SELECTED"
        echo "Symlink $SELECTED dihapus dari sites-enabled."
      else
        echo "File ini bukan symlink di sites-enabled, tidak ada yang di-disable."
      fi
      ;;
    4)
      read -p "Yakin ingin menghapus permanen $SELECTED ? (ketik DELETE untuk konfirmasi): " CONFIRM_DEL
      if [ "$CONFIRM_DEL" = "DELETE" ]; then
        rm -f "$SELECTED"
        echo "File telah dihapus permanen."
        if [ -L "${NGINX_SITES_ENABLED}/${BASENAME}" ]; then
          rm -f "${NGINX_SITES_ENABLED}/${BASENAME}"
          echo "Symlink ${NGINX_SITES_ENABLED}/${BASENAME} juga dihapus."
        fi
      else
        echo "Penghapusan dibatalkan."
      fi
      ;;
    0)
      echo "Membatalkan operasi untuk file ini."
      ;;
    *)
      echo "Aksi tidak dikenal."
      ;;
  esac

  echo ""
done

echo "Menjalankan nginx -t untuk memastikan konfigurasi valid..."
if nginx -t; then
  echo "Konfigurasi valid. Reload nginx..."
  systemctl reload nginx || echo "Gagal reload nginx, cek manual dengan 'systemctl status nginx'."
else
  echo "nginx -t gagal. Mohon periksa file konfigurasi sebelum reload service."
fi

