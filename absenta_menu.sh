#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

pause() {
  read -p "Tekan Enter untuk kembali ke menu..."
}

menu_app_server() {
  while true; do
    clear
    echo "=== 1. App Server (Backend + Frontend) ==="
    echo "1.1 Deploy app server baru"
    echo "1.2 Update app server"
    echo "0. Kembali"
    read -p "Pilih: " choice
    case "$choice" in
      1|1.1)
        bash "$SCRIPT_DIR/deploy_app_server.sh"
        pause
        ;;
      2|1.2)
        bash "$SCRIPT_DIR/update_app_server.sh"
        pause
        ;;
      0)
        break
        ;;
      *)
        echo "Pilihan tidak dikenal"
        pause
        ;;
    esac
  done
}

menu_backend_frontend() {
  while true; do
    clear
    echo "=== 2. Backend / Frontend Terpisah ==="
    echo "2.1 Deploy backend server"
    echo "2.2 Deploy frontend server"
    echo "0. Kembali"
    read -p "Pilih: " choice
    case "$choice" in
      1|2.1)
        bash "$SCRIPT_DIR/deploy_backend_server.sh"
        pause
        ;;
      2|2.2)
        bash "$SCRIPT_DIR/deploy_frontend_server.sh"
        pause
        ;;
      0)
        break
        ;;
      *)
        echo "Pilihan tidak dikenal"
        pause
        ;;
    esac
  done
}

menu_db_server() {
  while true; do
    clear
    echo "=== 3. Database Server (PostgreSQL) ==="
    echo "3.1 Deploy PostgreSQL server"
    echo "0. Kembali"
    read -p "Pilih: " choice
    case "$choice" in
      1|3.1)
        bash "$SCRIPT_DIR/deploy_db_server.sh"
        pause
        ;;
      0)
        break
        ;;
      *)
        echo "Pilihan tidak dikenal"
        pause
        ;;
    esac
  done
}

menu_redis_server() {
  while true; do
    clear
    echo "=== 4. Redis Server ==="
    echo "4.1 Deploy Redis server"
    echo "0. Kembali"
    read -p "Pilih: " choice
    case "$choice" in
      1|4.1)
        bash "$SCRIPT_DIR/deploy_redis_server.sh"
        pause
        ;;
      0)
        break
        ;;
      *)
        echo "Pilihan tidak dikenal"
        pause
        ;;
    esac
  done
}

menu_worker_server() {
  while true; do
    clear
    echo "=== 5. Worker Server ==="
    echo "5.1 Deploy worker server"
    echo "5.2 Update worker server"
    echo "0. Kembali"
    read -p "Pilih: " choice
    case "$choice" in
      1|5.1)
        bash "$SCRIPT_DIR/deploy_worker_server.sh"
        pause
        ;;
      2|5.2)
        bash "$SCRIPT_DIR/update_worker_server.sh"
        pause
        ;;
      0)
        break
        ;;
      *)
        echo "Pilihan tidak dikenal"
        pause
        ;;
    esac
  done
}

menu_nginx() {
  while true; do
    clear
    echo "=== 6. Nginx Reverse Proxy ==="
    echo "6.1 Deploy/Update Nginx reverse proxy untuk app/api"
    echo "0. Kembali"
    read -p "Pilih: " choice
    case "$choice" in
      1|6.1)
        bash "$SCRIPT_DIR/deploy_nginx_proxy.sh"
        pause
        ;;
      0)
        break
        ;;
      *)
        echo "Pilihan tidak dikenal"
        pause
        ;;
    esac
  done
}

menu_wireguard() {
  while true; do
    clear
    echo "=== 7. WireGuard VPN ==="
    echo "7.1 Setup WireGuard client di server aplikasi/DB/Redis"
    echo "7.2 Tambah client di server WireGuard"
    echo "7.3 Hapus client di server WireGuard"
    echo "7.4 Cek status WireGuard (wg show)"
    echo "7.5 Restart layanan WireGuard (wg-quick@IFACE)"
    echo "7.6 Uji konektivitas ping antar IP WireGuard"
    echo "7.7 Lihat konfigurasi WireGuard (wg0.conf)"
    echo "7.8 Jalankan tcpdump ICMP di interface WireGuard"
    echo "7.9 Tampilkan key WireGuard (PublicKey dari PrivateKey interface)"
    echo "0. Kembali"
    read -p "Pilih: " choice
    case "$choice" in
      1|7.1)
        bash "$SCRIPT_DIR/setup_wireguard_client.sh"
        pause
        ;;
      2|7.2)
        bash "$SCRIPT_DIR/add_wireguard_client.sh"
        pause
        ;;
      3|7.3)
        bash "$SCRIPT_DIR/delete_wireguard_client.sh"
        pause
        ;;
      4|7.4)
        read -p "Nama interface WireGuard (default wg0): " WG_IFACE
        WG_IFACE=${WG_IFACE:-wg0}
        echo "Status WireGuard untuk $WG_IFACE:"
        wg show "$WG_IFACE" || echo "Interface $WG_IFACE tidak aktif atau wg belum terpasang."
        pause
        ;;
      5|7.5)
        read -p "Nama interface WireGuard (default wg0): " WG_IFACE
        WG_IFACE=${WG_IFACE:-wg0}
        echo "Restart layanan wg-quick@$WG_IFACE..."
        systemctl restart "wg-quick@$WG_IFACE" || echo "Gagal restart wg-quick@$WG_IFACE"
        systemctl status "wg-quick@$WG_IFACE" --no-pager -l | head -n 20 || true
        pause
        ;;
      6|7.6)
        read -p "IP sumber (kosongkan untuk default IP server ini): " SRC_IP
        read -p "IP tujuan WireGuard yang ingin di-ping (contoh 10.50.0.1): " TARGET_IP
        if [ -z "$TARGET_IP" ]; then
          echo "IP tujuan wajib diisi."
          pause
        else
          if [ -n "$SRC_IP" ]; then
            echo "Ping dari server ini ke $TARGET_IP (source IP tidak dapat diatur langsung via ping standar)"
          fi
          ping -c 4 "$TARGET_IP" || echo "Ping ke $TARGET_IP gagal."
          pause
        fi
        ;;
      7|7.7)
        read -p "Nama interface WireGuard (default wg0): " WG_IFACE
        WG_IFACE=${WG_IFACE:-wg0}
        WG_CONF="/etc/wireguard/$WG_IFACE.conf"
        if [ -f "$WG_CONF" ]; then
          echo "Isi konfigurasi $WG_CONF:"
          sed -n '1,200p' "$WG_CONF"
        else
          echo "File konfigurasi $WG_CONF tidak ditemukan."
        fi
        pause
        ;;
      8|7.8)
        read -p "Nama interface WireGuard (default wg0): " WG_IFACE
        WG_IFACE=${WG_IFACE:-wg0}
        if ! command -v tcpdump >/dev/null 2>&1; then
          echo "tcpdump belum terpasang. Install dengan: apt install tcpdump"
          pause
        else
          echo "Menjalankan tcpdump untuk ICMP di interface $WG_IFACE. Tekan Ctrl+C untuk berhenti."
          tcpdump -n -i "$WG_IFACE" icmp
          pause
        fi
        ;;
      9|7.9)
        read -p "Nama interface WireGuard (default wg0): " WG_IFACE
        WG_IFACE=${WG_IFACE:-wg0}
        WG_CONF="/etc/wireguard/$WG_IFACE.conf"
        if [ ! -f "$WG_CONF" ]; then
          echo "File konfigurasi $WG_CONF tidak ditemukan."
          pause
        else
          PRIVATE_LINE=$(grep -m1 '^PrivateKey' "$WG_CONF" || true)
          if [ -z "$PRIVATE_LINE" ]; then
            echo "Tidak menemukan PrivateKey di $WG_CONF."
          else
            PRIVATE_KEY=$(printf "%s" "$PRIVATE_LINE" | awk -F'= ' '{print $2}')
            if [ -z "$PRIVATE_KEY" ]; then
              echo "Gagal membaca nilai PrivateKey dari $WG_CONF."
            else
              PUB_FROM_CONF=$(printf "%s" "$PRIVATE_KEY" | wg pubkey 2>/dev/null || true)
              if [ -z "$PUB_FROM_CONF" ]; then
                echo "Gagal menghitung PublicKey dari PrivateKey."
              else
                echo "PublicKey hasil dari PrivateKey interface di $WG_CONF:"
                echo "$PUB_FROM_CONF"
              fi
            fi
          fi
          echo ""
          echo "PublicKey yang sedang aktif menurut wg show:"
          if command -v wg >/dev/null 2>&1; then
            wg show "$WG_IFACE" | sed -n '1,80p' || echo "Gagal menjalankan wg show."
          else
            echo "Perintah wg tidak ditemukan."
          fi
          pause
        fi
        ;;
      0)
        break
        ;;
      *)
        echo "Pilihan tidak dikenal"
        pause
        ;;
    esac
  done
}

menu_security() {
  while true; do
    clear
    echo "=== 8. Keamanan Server ==="
    echo "8.1 Hardening dasar server (UFW, fail2ban, SSH opsi)"
    echo "0. Kembali"
    read -p "Pilih: " choice
    case "$choice" in
      1|8.1)
        bash "$SCRIPT_DIR/harden_server.sh"
        pause
        ;;
      0)
        break
        ;;
      *)
        echo "Pilihan tidak dikenal"
        pause
        ;;
    esac
  done
}

menu_diagnostics() {
  while true; do
    clear
    echo "=== 9. Diagnostik & Report Server ==="
    echo "9.1 Report App Server (backend + frontend lokal)"
    echo "9.2 Diagnosa Nginx & domain"
    echo "9.3 Diagnosa Redis"
    echo "9.4 Diagnosa Koneksi Database (TCP saja)"
    echo "0. Kembali"
    read -p "Pilih: " choice
    case "$choice" in
      1|9.1)
        echo "=== Report App Server ==="
        echo ""
        echo "--- Informasi sistem dasar ---"
        hostname
        echo ""
        echo "Uptime:"
        uptime || true
        echo ""
        echo "--- PM2 status ---"
        if command -v pm2 >/dev/null 2>&1; then
          pm2 list || true
        else
          echo "pm2 tidak ditemukan."
        fi
        echo ""
        echo "--- Service Node.js yang listen di port umum (3000/8080) ---"
        ss -plnt 2>/dev/null | grep -E '(:3000|:8080)' || echo "Tidak ada proses yang listen di 3000/8080 atau ss tidak tersedia."
        echo ""
        echo "--- Cek health backend via localhost (jika ada) ---"
        if command -v curl >/dev/null 2>&1; then
          echo "Mencoba curl http://127.0.0.1:3000/health ..."
          curl -sS -o /tmp/absenta_backend_health.txt -w "\nHTTP %{http_code}\n" http://127.0.0.1:3000/health || echo "Gagal curl backend health."
          echo "Response (maks 40 baris):"
          sed -n '1,40p' /tmp/absenta_backend_health.txt 2>/dev/null || true
          rm -f /tmp/absenta_backend_health.txt || true
        else
          echo "curl tidak ditemukan."
        fi
        echo ""
        echo "--- Cek environment backend (hanya key penting jika ada) ---"
        BACKEND_ENV="$SCRIPT_DIR/backend/.env"
        if [ -f "$BACKEND_ENV" ]; then
          grep -E '^(DATABASE_URL|REDIS_URL|APP_URL|FRONTEND_URL|BACKEND_URL|API_BASE_URL)=' "$BACKEND_ENV" || echo "Key penting tidak ditemukan di .env."
        else
          echo "File backend/.env tidak ditemukan relatif terhadap $SCRIPT_DIR."
        fi
        pause
        ;;
      2|9.2)
        echo "=== Diagnosa Nginx & Domain ==="
        if ! command -v nginx >/dev/null 2>&1; then
          echo "nginx tidak terpasang di server ini."
          pause
        else
          echo "--- nginx -t ---"
          nginx -t || true
          echo ""
          echo "--- systemctl status nginx (20 baris pertama) ---"
          systemctl status nginx --no-pager -l | head -n 20 || true
          echo ""
          if command -v curl >/dev/null 2>&1; then
            read -p "Masukkan domain frontend untuk dicek (contoh www.absenta.id): " FRONT_DOMAIN
            if [ -n "$FRONT_DOMAIN" ]; then
              echo ""
              echo "--- HTTP header untuk http://$FRONT_DOMAIN ---"
              curl -I --max-time 10 "http://$FRONT_DOMAIN" || echo "Gagal curl http://$FRONT_DOMAIN"
              echo ""
              echo "--- HTTP header untuk https://$FRONT_DOMAIN (jika HTTPS) ---"
              curl -I -k --max-time 10 "https://$FRONT_DOMAIN" || echo "Gagal curl https://$FRONT_DOMAIN"
            else
              echo "Domain kosong, lewati cek curl."
            fi
          else
            echo "curl tidak ditemukan."
          fi
          pause
        fi
        ;;
      3|9.3)
        echo "=== Diagnosa Redis ==="
        if ! command -v redis-cli >/dev/null 2>&1; then
          echo "redis-cli tidak ditemukan. Pastikan Redis terpasang di server ini."
          pause
        else
          read -p "Host Redis (default 127.0.0.1): " REDIS_HOST
          REDIS_HOST=${REDIS_HOST:-127.0.0.1}
          read -p "Port Redis (default 6379): " REDIS_PORT
          REDIS_PORT=${REDIS_PORT:-6379}
          echo ""
          echo "--- redis-cli PING ---"
          redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" PING || echo "PING ke Redis gagal."
          echo ""
          echo "--- redis-cli INFO server (ringkas) ---"
          redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" INFO server | sed -n '1,40p' || echo "Gagal ambil INFO server."
          echo ""
          echo "--- redis-cli INFO stats (ringkas) ---"
          redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" INFO stats | sed -n '1,40p' || echo "Gagal ambil INFO stats."
          pause
        fi
        ;;
      4|9.4)
        echo "=== Diagnosa Koneksi Database (TCP) ==="
        read -p "Host DB (contoh 10.50.0.3 atau 127.0.0.1): " DB_HOST
        read -p "Port DB (default 5432): " DB_PORT
        DB_PORT=${DB_PORT:-5432}
        echo ""
        echo "--- Cek koneksi TCP ke $DB_HOST:$DB_PORT ---"
        if command -v nc >/dev/null 2>&1; then
          nc -zv "$DB_HOST" "$DB_PORT" || echo "Koneksi TCP ke $DB_HOST:$DB_PORT gagal."
        elif command -v telnet >/dev/null 2>&1; then
          echo "telnet $DB_HOST $DB_PORT (tekan Ctrl+] lalu 'quit' untuk keluar)"
          telnet "$DB_HOST" "$DB_PORT" || echo "Koneksi telnet gagal."
        else
          echo "nc/telnet tidak tersedia. Install salah satunya untuk tes TCP."
        fi
        pause
        ;;
      0)
        break
        ;;
      *)
        echo "Pilihan tidak dikenal"
        pause
        ;;
    esac
  done
}

menu_pm2() {
  while true; do
    clear
    echo "=== 10. PM2 & Monitoring Proses ==="
    echo "10.1 Lihat daftar proses PM2"
    echo "10.2 Restart proses tertentu"
    echo "10.3 Restart semua proses"
    echo "10.4 Stop semua proses"
    echo "10.5 Tampilkan log proses tertentu (100 baris terakhir)"
    echo "10.6 Simpan dan pastikan PM2 autostart (pm2 save + startup)"
    echo "0. Kembali"
    read -p "Pilih: " choice
    case "$choice" in
      1|10.1)
        if command -v pm2 >/dev/null 2>&1; then
          pm2 list || true
        else
          echo "pm2 tidak ditemukan di PATH."
        fi
        pause
        ;;
      2|10.2)
        if ! command -v pm2 >/dev/null 2>&1; then
          echo "pm2 tidak ditemukan di PATH."
          pause
        else
          pm2 list || true
          read -p "Masukkan nama atau id proses PM2 yang akan direstart: " PM2_NAME
          if [ -n "$PM2_NAME" ]; then
            pm2 restart "$PM2_NAME" || echo "Gagal restart proses PM2 $PM2_NAME"
          else
            echo "Nama/id proses kosong, batal."
          fi
          pause
        fi
        ;;
      3|10.3)
        if command -v pm2 >/dev/null 2>&1; then
          pm2 restart all || echo "Gagal restart semua proses PM2."
        else
          echo "pm2 tidak ditemukan di PATH."
        fi
        pause
        ;;
      4|10.4)
        if command -v pm2 >/dev/null 2>&1; then
          pm2 stop all || echo "Gagal stop semua proses PM2."
        else
          echo "pm2 tidak ditemukan di PATH."
        fi
        pause
        ;;
      5|10.5)
        if ! command -v pm2 >/dev/null 2>&1; then
          echo "pm2 tidak ditemukan di PATH."
          pause
        else
          pm2 list || true
          read -p "Masukkan nama atau id proses PM2 untuk lihat log: " PM2_NAME
          if [ -n "$PM2_NAME" ]; then
            pm2 logs "$PM2_NAME" --lines 100 || echo "Gagal menampilkan log proses $PM2_NAME"
          else
            echo "Nama/id proses kosong, batal."
          fi
          pause
        fi
        ;;
      6|10.6)
        if command -v pm2 >/dev/null 2>&1; then
          pm2 save || echo "Gagal menjalankan pm2 save."
          if command -v systemctl >/dev/null 2>&1; then
            pm2 startup systemd -u root --hp /root || true
          fi
        else
          echo "pm2 tidak ditemukan di PATH."
        fi
        pause
        ;;
      0)
        break
        ;;
      *)
        echo "Pilihan tidak dikenal"
        pause
        ;;
    esac
  done
}

while true; do
  clear
  echo "===== ABSENTA DEPLOY MENU ====="
  echo "1. App Server (backend + frontend)"
  echo "2. Backend / Frontend terpisah"
  echo "3. Database Server (PostgreSQL)"
  echo "4. Redis Server"
  echo "5. Worker Server"
  echo "6. Nginx Reverse Proxy"
  echo "7. WireGuard VPN"
  echo "8. Keamanan Server (Hardening)"
  echo "9. Diagnostik & Report"
  echo "10. PM2 & Monitoring Proses"
  echo "0. Keluar"
  read -p "Pilih menu: " main_choice
  case "$main_choice" in
    1)
      menu_app_server
      ;;
    2)
      menu_backend_frontend
      ;;
    3)
      menu_db_server
      ;;
    4)
      menu_redis_server
      ;;
    5)
      menu_worker_server
      ;;
    6)
      menu_nginx
      ;;
    7)
      menu_wireguard
      ;;
    8)
      menu_security
      ;;
    9)
      menu_diagnostics
      ;;
    10)
      menu_pm2
      ;;
    0)
      echo "Keluar."
      exit 0
      ;;
    *)
      echo "Pilihan tidak dikenal"
      pause
      ;;
  esac
done
