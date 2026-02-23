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
