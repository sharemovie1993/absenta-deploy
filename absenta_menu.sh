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
    echo "1.3 Rebuild Backend (npm run build)"
    echo "1.4 Rebuild Frontend (npm run build)"
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
      3|1.3)
        rebuild_backend_app
        pause
        ;;
      4|1.4)
        rebuild_frontend_app
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

db_status() {
  echo "=== Status Database PostgreSQL ==="
  if command -v systemctl >/dev/null 2>&1; then
    echo ""
    echo "Status service:"
    systemctl is-active postgresql 2>/dev/null || echo "Gagal membaca status service postgresql."
  else
    echo "systemctl tidak tersedia."
  fi
  if command -v psql >/dev/null 2>&1; then
    echo ""
    echo "Konfigurasi runtime:"
    LISTEN_ADDR=$(sudo -u postgres psql -tAc "SHOW listen_addresses;" 2>/dev/null || echo "unknown")
    PORT_VAL=$(sudo -u postgres psql -tAc "SHOW port;" 2>/dev/null || echo "unknown")
    echo "  listen_addresses = $LISTEN_ADDR"
    echo "  port            = $PORT_VAL"
    echo ""
    echo "Informasi versi:"
    sudo -u postgres psql -tAc "SELECT version();" || echo "Gagal mengambil versi PostgreSQL."
  else
    echo "psql tidak ditemukan di PATH, tidak bisa membaca konfigurasi runtime."
  fi
  echo ""
  echo "Socket yang listen (postgres):"
  if command -v ss >/dev/null 2>&1; then
    ss -plnt 2>/dev/null | grep postgres || echo "Tidak ada socket postgres terdeteksi atau ss tidak tersedia."
  elif command -v netstat >/dev/null 2>&1; then
    netstat -plnt 2>/dev/null | grep postgres || echo "Tidak ada socket postgres terdeteksi."
  else
    echo "ss/netstat tidak tersedia."
  fi
}

db_show_config() {
  CONF_PATH=$(find /etc/postgresql -maxdepth 3 -type f -name 'postgresql.conf' 2>/dev/null | head -n1)
  if [ -z "$CONF_PATH" ] || [ ! -f "$CONF_PATH" ]; then
    echo "postgresql.conf tidak ditemukan di /etc/postgresql."
    return
  fi
  HBA_PATH="$(dirname "$CONF_PATH")/pg_hba.conf"
  echo "postgresql.conf: $CONF_PATH"
  if command -v less >/dev/null 2>&1; then
    echo "Membuka postgresql.conf dengan less (mode scroll)."
    less "$CONF_PATH"
  else
    sed -n '1,200p' "$CONF_PATH" || true
  fi
  echo ""
  if [ -f "$HBA_PATH" ]; then
    echo "pg_hba.conf: $HBA_PATH"
    if command -v less >/dev/null 2>&1; then
      echo "Membuka pg_hba.conf dengan less (mode scroll)."
      less "$HBA_PATH"
    else
      sed -n '1,160p' "$HBA_PATH" || true
    fi
  else
    echo "pg_hba.conf tidak ditemukan berdampingan dengan postgresql.conf."
  fi
}

db_restart() {
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart postgresql || echo "Gagal restart service postgresql."
    systemctl status postgresql --no-pager -l | head -n 15 || true
  else
    echo "systemctl tidak tersedia, tidak bisa restart postgresql."
  fi
}

db_backup() {
  if ! command -v pg_dump >/dev/null 2>&1; then
    echo "pg_dump tidak ditemukan. Pastikan paket postgresql-client terpasang."
    return
  fi
  read -p "Nama database yang akan di-backup (default absensi): " BK_DB_NAME
  BK_DB_NAME=${BK_DB_NAME:-absensi}
  read -p "Direktori tujuan backup (default /var/backups/postgresql): " BK_DIR
  BK_DIR=${BK_DIR:-/var/backups/postgresql}
  mkdir -p "$BK_DIR" || { echo "Gagal membuat direktori $BK_DIR"; return; }
  TS="$(date +%Y%m%d%H%M%S)"
  BK_FILE="${BK_DIR}/${BK_DB_NAME}_${TS}.dump"
  echo "Membuat backup database $BK_DB_NAME ke $BK_FILE"
  sudo -u postgres pg_dump -Fc "$BK_DB_NAME" > "$BK_FILE" || { echo "Backup gagal."; rm -f "$BK_FILE"; return; }
  echo "Backup selesai."
}

db_restore() {
  if ! command -v pg_restore >/dev/null 2>&1; then
    echo "pg_restore tidak ditemukan. Pastikan paket postgresql-client terpasang."
    return
  fi
  read -p "Path file backup (.dump) yang akan direstore: " BK_FILE
  if [ ! -f "$BK_FILE" ]; then
    echo "File $BK_FILE tidak ditemukan."
    return
  fi
  read -p "Nama database tujuan restore (default absensi): " RS_DB_NAME
  RS_DB_NAME=${RS_DB_NAME:-absensi}
  read -p "Drop isi database sebelum restore (clean)? (y/n, default n): " RS_CLEAN
  RS_CLEAN=${RS_CLEAN:-n}
  EXTRA_FLAGS=""
  if [ "$RS_CLEAN" = "y" ] || [ "$RS_CLEAN" = "Y" ]; then
    EXTRA_FLAGS="-c"
  fi
  echo "Menjalankan restore ke database $RS_DB_NAME dari $BK_FILE"
  sudo -u postgres pg_restore $EXTRA_FLAGS -d "$RS_DB_NAME" "$BK_FILE" || { echo "Restore gagal."; return; }
  echo "Restore selesai."
}

db_show_size() {
  if ! command -v psql >/dev/null 2>&1; then
    echo "psql tidak ditemukan di PATH."
    return
  fi
  echo "Ukuran per database:"
  sudo -u postgres psql -x -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size FROM pg_database ORDER BY pg_database_size(datname) DESC;" | sed -n '1,80p' || echo "Gagal mengambil ukuran database."
  echo ""
  read -p "Tampilkan ukuran tabel untuk database tertentu? (y/n, default n): " SHOW_TABLES
  SHOW_TABLES=${SHOW_TABLES:-n}
  if [ "$SHOW_TABLES" = "y" ] || [ "$SHOW_TABLES" = "Y" ]; then
    read -p "Nama database (default absensi): " SZ_DB_NAME
    SZ_DB_NAME=${SZ_DB_NAME:-absensi}
    sudo -u postgres psql -d "$SZ_DB_NAME" -x -c "SELECT schemaname, relname, pg_size_pretty(pg_total_relation_size(quote_ident(schemaname)||'.'||quote_ident(relname))) AS size FROM pg_stat_user_tables ORDER BY pg_total_relation_size(quote_ident(schemaname)||'.'||quote_ident(relname)) DESC;" | sed -n '1,80p' || echo "Gagal mengambil ukuran tabel."
  fi
}

menu_db_server() {
db_set_superuser_password() {
  if ! command -v psql >/dev/null 2>&1; then
    echo "psql tidak ditemukan di PATH."
    return
  fi
  read -p "Nama role superuser (default postgres): " DB_SUPERUSER
  DB_SUPERUSER=${DB_SUPERUSER:-postgres}
  read -s -p "Password baru untuk role $DB_SUPERUSER: " DB_PASS
  echo ""
  if [ -z "$DB_PASS" ]; then
    echo "Password tidak boleh kosong."
    return
  fi
  ESCAPED_PASS=${DB_PASS//\'/\'\'}
  echo "Mengatur password untuk role $DB_SUPERUSER ..."
  sudo -u postgres psql -c "ALTER ROLE \"$DB_SUPERUSER\" WITH PASSWORD '$ESCAPED_PASS';" || echo "Gagal mengatur password role $DB_SUPERUSER."
}

db_reset_user_password() {
  if ! command -v psql >/dev/null 2>&1; then
    echo "psql tidak ditemukan di PATH."
    return
  fi
  echo "Daftar user database saat ini:"
  sudo -u postgres psql -t -c "SELECT usename FROM pg_user ORDER BY usename;" 2>/dev/null | awk 'NF {print "- "$1}' || echo "Gagal mengambil daftar user."
  echo ""
  read -p "Nama user database yang akan di-reset password-nya: " DB_USER
  if [ -z "$DB_USER" ]; then
    echo "Nama user tidak boleh kosong."
    return
  fi
  read -s -p "Password baru untuk user $DB_USER: " DB_PASS
  echo ""
  if [ -z "$DB_PASS" ]; then
    echo "Password tidak boleh kosong."
    return
  fi
  ESCAPED_PASS=${DB_PASS//\'/\'\'}
  echo "Mengatur password baru untuk user $DB_USER ..."
  sudo -u postgres psql -c "ALTER ROLE \"$DB_USER\" WITH PASSWORD '$ESCAPED_PASS';" || echo "Gagal mengatur password user $DB_USER."
}

db_tune_production() {
  CONF_PATH=$(find /etc/postgresql -maxdepth 3 -type f -name 'postgresql.conf' 2>/dev/null | head -n1)
  if [ -z "$CONF_PATH" ] || [ ! -f "$CONF_PATH" ]; then
    echo "postgresql.conf tidak ditemukan di /etc/postgresql."
    return
  fi
  echo "postgresql.conf terdeteksi di: $CONF_PATH"
  read -p "max_connections (default 200): " MAX_CONN
  MAX_CONN=${MAX_CONN:-200}
  read -p "shared_buffers (default 1GB, contoh 512MB/2GB): " SHARED_BUFFERS
  SHARED_BUFFERS=${SHARED_BUFFERS:-1GB}
  read -p "work_mem (default 16MB): " WORK_MEM
  WORK_MEM=${WORK_MEM:-16MB}
  TS="$(date +%Y%m%d%H%M%S)"
  cp "$CONF_PATH" "${CONF_PATH}.bak_tuning_$TS" || { echo "Gagal membuat backup $CONF_PATH"; return; }
  cat >> "$CONF_PATH" <<EOF

# absenta production tuning
max_connections = $MAX_CONN
shared_buffers = $SHARED_BUFFERS
work_mem = $WORK_MEM
EOF
  echo "Konfigurasi tuning ditambahkan ke $CONF_PATH"
  db_restart
}

db_seed_initial() {
  APP_ROOT="${APP_ROOT:-/var/www/absenta}"
  BACKEND_DIR="$APP_ROOT/backend"
  if [ ! -d "$BACKEND_DIR" ]; then
    echo "Direktori backend $BACKEND_DIR tidak ditemukan."
    echo "Pastikan app server sudah dideploy terlebih dahulu."
    return
  fi
  if ! command -v npx >/dev/null 2>&1; then
    echo "npx tidak ditemukan. Pastikan Node.js dan npm sudah terpasang."
    return
  fi
  cd "$BACKEND_DIR" || return
  echo "Menjalankan seed data awal Prisma (npx prisma db seed) di $BACKEND_DIR ..."
  npx prisma db seed || echo "Seed data awal gagal. Periksa log di atas."
}

  while true; do
    clear
    echo "=== 3. Database Server (PostgreSQL) ==="
    echo "3.1 Deploy PostgreSQL server"
    echo "3.2 Setup/konfigurasi DB untuk aplikasi"
    echo "3.3 Status database"
    echo "3.4 Lihat konfigurasi database"
    echo "3.5 Restart database"
    echo "3.6 Backup database"
    echo "3.7 Restore database dari backup"
    echo "3.8 Lihat ukuran database/tabel"
    echo "3.9 Set password superuser postgres"
    echo "3.10 Reset password user database"
    echo "3.11 Tuning produksi (max_connections, shared_buffers, work_mem)"
    echo "3.12 Seed data awal (Prisma db seed)"
    echo "0. Kembali"
    read -p "Pilih: " choice
    case "$choice" in
      1|3.1)
        bash "$SCRIPT_DIR/deploy_db_server.sh"
        pause
        ;;
      2|3.2)
        bash "$SCRIPT_DIR/setup_db_server_config.sh"
        pause
        ;;
      3|3.3)
        db_status
        pause
        ;;
      4|3.4)
        db_show_config
        pause
        ;;
      5|3.5)
        db_restart
        pause
        ;;
      6|3.6)
        db_backup
        pause
        ;;
      7|3.7)
        db_restore
        pause
        ;;
      8|3.8)
        db_show_size
        pause
        ;;
      9|3.9)
        db_set_superuser_password
        pause
        ;;
      10|3.10)
        db_reset_user_password
        pause
        ;;
      11|3.11)
        db_tune_production
        pause
        ;;
      12|3.12)
        db_seed_initial
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
    echo "6.2 Backup/Hapus konfigurasi Nginx lama (cek konflik server_name)"
    echo "0. Kembali"
    read -p "Pilih: " choice
    case "$choice" in
      1|6.1)
        bash "$SCRIPT_DIR/deploy_nginx_proxy.sh"
        pause
        ;;
      2|6.2)
        bash "$SCRIPT_DIR/cleanup_nginx_legacy.sh"
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

menu_wireguard_server_side() {
  while true; do
    clear
    echo "=== WireGuard Server Side ==="
    echo "1. Tambah Client"
    echo "2. Hapus Client"
    echo "3. Edit Client"
    echo "4. Setup WireGuard Client di server aplikasi/DB/Redis"
    echo "0. Kembali"
    read -p "Pilih: " choice
    case "$choice" in
      1)
        bash "$SCRIPT_DIR/add_wireguard_client.sh"
        pause
        ;;
      2)
        bash "$SCRIPT_DIR/delete_wireguard_client.sh"
        pause
        ;;
      3)
        bash "$SCRIPT_DIR/edit_wireguard_client.sh"
        pause
        ;;
      4)
        bash "$SCRIPT_DIR/setup_wireguard_client.sh"
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
    echo "=== WireGuard VPN ==="
    echo "1. Deploy WireGuard Server"
    echo "2. Show Public Key"
    echo "3. Lihat Konfigurasi"
    echo "4. Server Side (Tambah/Hapus/Setup Client)"
    echo "5. Status WireGuard (service + peer)"
    echo "0. Kembali"
    read -p "Pilih: " choice
    case "$choice" in
      1)
        bash "$SCRIPT_DIR/deploy_wireguard_server.sh"
        pause
        ;;
      2)
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
      3)
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
      4)
        menu_wireguard_server_side
        ;;
      5)
        read -p "Nama interface WireGuard (default wg0): " WG_IFACE
        WG_IFACE=${WG_IFACE:-wg0}
        echo "=== Status WireGuard untuk $WG_IFACE ==="
        if command -v systemctl >/dev/null 2>&1; then
          echo "--- systemctl status wg-quick@$WG_IFACE (20 baris pertama) ---"
          systemctl status "wg-quick@$WG_IFACE" --no-pager -l | head -n 20 || echo "Gagal membaca status service wg-quick@$WG_IFACE."
          echo ""
        else
          echo "systemctl tidak ditemukan, lewati status service."
        fi
        if command -v wg >/dev/null 2>&1; then
          echo "--- wg show $WG_IFACE ---"
          wg show "$WG_IFACE" 2>/dev/null || echo "wg show gagal atau interface $WG_IFACE tidak aktif."
        else
          echo "Perintah wg tidak ditemukan. Pastikan wireguard-tools terpasang."
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

menu_env_config() {
  while true; do
    clear
    echo "=== Konfigurasi Environment ==="
    echo "1. .env backend"
    echo "2. .env frontend"
    echo "0. Kembali"
    read -p "Pilih: " choice
    case "$choice" in
      1)
        if ! command -v nano >/dev/null 2>&1; then
          apt update -y
          apt install -y nano
        fi
        nano /var/www/absenta/backend/.env
        ;;
      2)
        if ! command -v nano >/dev/null 2>&1; then
          apt update -y
          apt install -y nano
        fi
        nano /var/www/absenta/frontend/.env
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

ensure_netplan_available() {
  if command -v netplan >/dev/null 2>&1; then
    return 0
  fi
  echo "netplan tidak ditemukan di sistem."
  if command -v apt-get >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then
    read -p "Install paket netplan.io sekarang? (y/n, default n): " INSTALL_NETPLAN
    INSTALL_NETPLAN=${INSTALL_NETPLAN:-n}
    case "$INSTALL_NETPLAN" in
      y|Y)
        if command -v apt-get >/dev/null 2>&1; then
          apt-get update -y && apt-get install -y netplan.io || { echo "Install netplan.io gagal."; return 1; }
        else
          apt update -y && apt install -y netplan.io || { echo "Install netplan.io gagal."; return 1; }
        fi
        ;;
      *)
        echo "Konfigurasi IP dibatalkan karena netplan tidak tersedia."
        return 1
        ;;
    esac
  else
    echo "apt/apt-get tidak ditemukan. Install netplan.io secara manual."
    return 1
  fi
  if ! command -v netplan >/dev/null 2>&1; then
    echo "netplan masih belum tersedia setelah instalasi."
    return 1
  fi
  return 0
}

print_available_interfaces() {
  echo "Daftar interface network yang terdeteksi:"
  if command -v ip >/dev/null 2>&1; then
    ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$'
  elif command -v ifconfig >/dev/null 2>&1; then
    ifconfig -a | sed 's/[ \t].*//;/^\(lo\|\)$/d'
  else
    echo "Perintah ip/ifconfig tidak ditemukan. Tidak bisa mendeteksi interface otomatis."
  fi
}

restart_network_services() {
  echo "=== Restart Layanan Jaringan ==="
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemctl tidak ditemukan. Silakan restart layanan jaringan manual sesuai distro."
    return
  fi
  restarted_any=0
  for svc in systemd-networkd NetworkManager networking; do
    if systemctl list-unit-files | grep -q "^$svc\.service"; then
      echo "- Restart $svc ..."
      if systemctl restart "$svc"; then
        echo "  $svc: OK"
        restarted_any=1
      else
        echo "  $svc: GAGAL (cek systemctl status $svc)"
      fi
    fi
  done
  if [ "$restarted_any" -eq 0 ]; then
    echo "Tidak menemukan layanan jaringan standar (systemd-networkd/NetworkManager/networking)."
    echo "Silakan cek layanan jaringan spesifik di server ini."
  fi
}

configure_ip_dhcp() {
  ensure_netplan_available || return
  print_available_interfaces
  read -p "Nama interface network yang akan dikonfigurasi (contoh ens3): " IFACE
  if [ -z "$IFACE" ]; then
    echo "Nama interface tidak boleh kosong."
    return
  fi
  NETPLAN_FILE="/etc/netplan/60-absenta-network.yaml"
  if [ -f "$NETPLAN_FILE" ]; then
    TS="$(date +%Y%m%d%H%M%S)"
    cp "$NETPLAN_FILE" "${NETPLAN_FILE}.bak_$TS" || true
  fi
  cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      dhcp4: true
EOF
  echo "Konfigurasi tersimpan di $NETPLAN_FILE"
  netplan apply || echo "Gagal menjalankan netplan apply. Silakan cek konfigurasi."
  restart_network_services
}

configure_ip_static() {
  ensure_netplan_available || return
  print_available_interfaces
  read -p "Nama interface network yang akan dikonfigurasi (contoh ens3): " IFACE
  if [ -z "$IFACE" ]; then
    echo "Nama interface tidak boleh kosong."
    return
  fi
  read -p "Alamat IP dengan CIDR (contoh 192.168.1.10/24): " IP_CIDR
  if [ -z "$IP_CIDR" ]; then
    echo "Alamat IP tidak boleh kosong."
    return
  fi
  read -p "Gateway (contoh 192.168.1.1): " GATEWAY
  if [ -z "$GATEWAY" ]; then
    echo "Gateway tidak boleh kosong."
    return
  fi
  read -p "DNS server (dipisah spasi, contoh 8.8.8.8 1.1.1.1): " DNS_SERVERS
  if [ -z "$DNS_SERVERS" ]; then
    DNS_SERVERS="8.8.8.8 1.1.1.1"
  fi
  NETPLAN_FILE="/etc/netplan/60-absenta-network.yaml"
  if [ -f "$NETPLAN_FILE" ]; then
    TS="$(date +%Y%m%d%H%M%S)"
    cp "$NETPLAN_FILE" "${NETPLAN_FILE}.bak_$TS" || true
  fi
  dns_list=$(printf "%s" "$DNS_SERVERS" | sed 's/ \+/, /g')
  cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $IFACE:
      addresses:
        - $IP_CIDR
      gateway4: $GATEWAY
      nameservers:
        addresses: [$dns_list]
EOF
  echo "Konfigurasi tersimpan di $NETPLAN_FILE"
  netplan apply || echo "Gagal menjalankan netplan apply. Silakan cek konfigurasi."
  restart_network_services
}

disable_dhcp_config() {
  ensure_netplan_available || return
  echo "=== Disable DHCP4 (netplan) ==="
  echo "Daftar file netplan saat ini:"
  ls -1 /etc/netplan 2>/dev/null || echo "Tidak ada file di /etc/netplan"
  echo ""
  echo "Langkah 1: Set dhcp4: false di semua file netplan yang ada."
  for file in /etc/netplan/*.yaml; do
    if [ -f "$file" ]; then
      TS="$(date +%Y%m%d%H%M%S)"
      cp "$file" "${file}.bak_$TS" || true
      sed -i 's/dhcp4:[ ]*true/dhcp4: false/g' "$file" || echo "Gagal mengubah $file"
    fi
  done
  echo ""
  echo "Status dhcp4 di file netplan setelah perubahan:"
  grep -n 'dhcp4:' /etc/netplan/*.yaml 2>/dev/null || echo "Tidak ada baris dhcp4 lagi di file .yaml."
  echo ""
  read -p "Nonaktifkan file netplan lain selain 60-absenta-network.yaml (rename menjadi .disabled)? (y/n, default n): " DISABLE_OTHERS
  DISABLE_OTHERS=${DISABLE_OTHERS:-n}
  case "$DISABLE_OTHERS" in
    y|Y)
      for file in /etc/netplan/*.yaml; do
        if [ -f "$file" ] && [ "$file" != "/etc/netplan/60-absenta-network.yaml" ]; then
          TS="$(date +%Y%m%d%H%M%S)"
          cp "$file" "${file}.bak_disable_$TS" || true
          mv "$file" "${file}.disabled" || echo "Gagal rename $file"
        fi
      done
      ;;
    *)
      echo "File netplan lain dibiarkan aktif."
      ;;
  esac
  netplan apply || echo "Gagal menjalankan netplan apply. Silakan cek konfigurasi."
  restart_network_services
}

show_current_ip() {
  echo "=== IP Address Saat Ini ==="
  if command -v ip >/dev/null 2>&1; then
    ip -4 addr show | awk '/^[0-9]+: /{iface=$2} /inet /{gsub(":", "", iface); print iface, $2}'
    echo ""
    echo "Default route:"
    ip route show default || true
  elif command -v ifconfig >/dev/null 2>&1; then
    ifconfig
  else
    echo "Perintah ip/ifconfig tidak ditemukan."
  fi
}

menu_ip_config() {
  while true; do
    clear
    echo "=== Konfigurasi IP Address ==="
    echo "1. Set IP Dynamic (DHCP)"
    echo "2. Set IP Static"
    echo "3. Cek IP Saat Ini"
    echo "4. Disable DHCP (netplan)"
    echo "5. Restart Layanan Jaringan"
    echo "0. Kembali"
    read -p "Pilih: " choice
    case "$choice" in
      1)
        configure_ip_dhcp
        pause
        ;;
      2)
        configure_ip_static
        pause
        ;;
      3)
        show_current_ip
        pause
        ;;
      4)
        disable_dhcp_config
        pause
        ;;
      5)
        restart_network_services
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

diagnose_app_server() {
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
}

diagnose_nginx() {
  echo "=== Diagnosa Nginx & Domain ==="
  if ! command -v nginx >/dev/null 2>&1; then
    echo "nginx tidak terpasang di server ini."
    return
  fi
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
}

diagnose_redis() {
  echo "=== Diagnosa Redis ==="
  if ! command -v redis-cli >/dev/null 2>&1; then
    echo "redis-cli tidak ditemukan. Pastikan Redis terpasang di server ini."
    return
  fi
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
}

diagnose_db() {
  echo "=== Diagnosa Koneksi Database (TCP) ==="
  read -p "Host DB (contoh 10.50.0.3 atau 127.0.0.1): " DB_HOST
  read -p "Port DB (default 5432): " DB_PORT
  DB_PORT=${DB_PORT:-5432}
  echo ""
  echo "--- Cek koneksi TCP ke $DB_HOST:$DB_PORT ---"
  if command -v nc >/dev/null 2>&1; then
    nc -zvw 5 "$DB_HOST" "$DB_PORT" || echo "Koneksi TCP ke $DB_HOST:$DB_PORT gagal atau timeout."
  elif command -v telnet >/dev/null 2>&1; then
    if command -v timeout >/dev/null 2>&1; then
      echo "Menggunakan telnet dengan timeout 5 detik..."
      timeout 5 telnet "$DB_HOST" "$DB_PORT" || echo "Koneksi telnet gagal atau timeout."
    else
      echo "telnet $DB_HOST $DB_PORT (tekan Ctrl+] lalu 'quit' untuk keluar)"
      telnet "$DB_HOST" "$DB_PORT" || echo "Koneksi telnet gagal."
    fi
  else
    echo "nc/telnet tidak tersedia. Install salah satunya untuk tes TCP."
  fi
}

wizard_cek_koneksi_db() {
  clear
  echo "=== Wizard Cek Koneksi ke Server PostgreSQL ==="
  echo ""
  echo "Wizard ini membantu menguji dari mesin INI ke server database PostgreSQL."
  echo "Langkah-langkah:"
  echo "  1) Cek ping ke host database"
  echo "  2) Cek port TCP PostgreSQL (default 5432)"
  echo "  3) (Opsional) Coba login ke database dengan psql"
  echo ""

  read -p "Hostname/IP server database (contoh 10.10.10.116): " DB_HOST
  if [ -z "$DB_HOST" ]; then
    echo "Hostname/IP tidak boleh kosong."
    return
  fi

  read -p "Port PostgreSQL (default 5432): " DB_PORT
  DB_PORT=${DB_PORT:-5432}

  echo ""
  echo "Langkah 1: Cek ping ke $DB_HOST ..."
  if command -v ping >/dev/null 2>&1; then
    ping -c 4 "$DB_HOST" || echo "Ping gagal (bisa jadi ICMP diblok, belum tentu DB down)."
  else
    echo "Perintah ping tidak ditemukan."
  fi

  echo ""
  echo "Langkah 2: Cek port TCP $DB_PORT di $DB_HOST ..."
  if command -v nc >/dev/null 2>&1; then
    nc -zvw 5 "$DB_HOST" "$DB_PORT" && echo "Port $DB_PORT TERBUKA." || echo "Port $DB_PORT TERTUTUP atau timeout/tidak bisa dijangkau."
  elif command -v telnet >/dev/null 2>&1; then
    if command -v timeout >/dev/null 2>&1; then
      echo "Menggunakan telnet dengan timeout 5 detik..."
      timeout 5 telnet "$DB_HOST" "$DB_PORT" || echo "Telnet gagal atau timeout membuka koneksi ke port $DB_PORT."
    else
      echo "Menggunakan telnet untuk cek port (Ctrl+] lalu quit untuk keluar jika tersambung)..."
      telnet "$DB_HOST" "$DB_PORT" || echo "Telnet gagal membuka koneksi ke port $DB_PORT."
    fi
  else
    echo "nc/telnet tidak ditemukan, lewati cek port."
  fi

  echo ""
  read -p "Coba test login PostgreSQL dengan psql dari mesin ini? (y/n, default n): " TEST_PSQL
  TEST_PSQL=${TEST_PSQL:-n}

  if [ "$TEST_PSQL" = "y" ] || [ "$TEST_PSQL" = "Y" ]; then
    if ! command -v psql >/dev/null 2>&1; then
      echo "psql tidak ditemukan. Instal paket postgresql-client terlebih dahulu."
      return
    fi

    read -p "Nama database (default postgres): " TEST_DB_NAME
    TEST_DB_NAME=${TEST_DB_NAME:-postgres}
    read -p "User PostgreSQL (default postgres): " TEST_DB_USER
    TEST_DB_USER=${TEST_DB_USER:-postgres}
    read -s -p "Password untuk user $TEST_DB_USER: " TEST_DB_PASS
    echo ""

    echo "Menjalankan: SELECT 1 sebagai test koneksi..."
    PGPASSWORD="$TEST_DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$TEST_DB_USER" -d "$TEST_DB_NAME" -c "SELECT 1;" && \
      echo "Koneksi PostgreSQL BERHASIL." || echo "Koneksi PostgreSQL GAGAL. Cek kembali pg_hba.conf, user, dan password."
  fi

  echo ""
  echo "Wizard cek koneksi selesai."
}

diagnose_pm2_simple() {
  echo "=== Diagnosa PM2 ==="
  if command -v pm2 >/dev/null 2>&1; then
    pm2 list || true
  else
    echo "pm2 tidak ditemukan di PATH."
  fi
}

backend_console_logs() {
  clear
  echo "=== Console Backend (PM2 logs absenta-backend) ==="
  if ! command -v pm2 >/dev/null 2>&1; then
    echo "pm2 tidak ditemukan di PATH."
    return
  fi
  if ! pm2 list | grep -q "absenta-backend"; then
    echo "Proses PM2 absenta-backend tidak ditemukan di PM2."
    return
  fi
  pm2 logs absenta-backend --lines 100 || echo "Gagal menampilkan log proses absenta-backend."
 }

diagnose_wireguard_ping() {
  read -p "IP tujuan WireGuard yang ingin di-ping (contoh 10.50.0.1): " TARGET_IP
  if [ -z "$TARGET_IP" ]; then
    echo "IP tujuan wajib diisi."
  else
    ping -c 4 "$TARGET_IP" || echo "Ping ke $TARGET_IP gagal."
  fi
}

diagnose_wireguard_tcpdump() {
  read -p "Nama interface WireGuard (default wg0): " WG_IFACE
  WG_IFACE=${WG_IFACE:-wg0}
  if ! command -v tcpdump >/dev/null 2>&1; then
    echo "tcpdump belum terpasang. Install dengan: apt install tcpdump"
  else
    echo "Menjalankan tcpdump untuk ICMP di interface $WG_IFACE. Tekan Ctrl+C untuk berhenti."
    tcpdump -n -i "$WG_IFACE" icmp
  fi
}

diagnose_wireguard_restart() {
  read -p "Nama interface WireGuard (default wg0): " WG_IFACE
  WG_IFACE=${WG_IFACE:-wg0}
  echo "Restart layanan wg-quick@$WG_IFACE..."
  systemctl restart "wg-quick@$WG_IFACE" || echo "Gagal restart wg-quick@$WG_IFACE"
  systemctl status "wg-quick@$WG_IFACE" --no-pager -l | head -n 20 || true
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

rebuild_backend_app() {
  APP_DIR="/var/www/absenta/backend"
  if [ ! -d "$APP_DIR" ]; then
    echo "Direktori $APP_DIR tidak ditemukan."
    return
  fi
  if ! command -v npm >/dev/null 2>&1; then
    echo "npm tidak ditemukan. Pastikan Node.js dan npm sudah terpasang."
    return
  fi
  cd "$APP_DIR" || return
  echo "Menjalankan npm run build untuk backend di $APP_DIR ..."
  if npm run build; then
    if command -v pm2 >/dev/null 2>&1; then
      if pm2 list | grep -q "absenta-backend"; then
        pm2 reload absenta-backend || echo "Gagal reload proses PM2 absenta-backend."
      else
        pm2 start dist/main.js --name absenta-backend --node-args "-r tsconfig-paths/register" || echo "Gagal start proses PM2 absenta-backend."
      fi
      pm2 save || true
    fi
  else
    echo "npm run build backend gagal. Cek log di atas."
  fi
}

rebuild_frontend_app() {
  APP_DIR="/var/www/absenta/frontend"
  if [ ! -d "$APP_DIR" ]; then
    echo "Direktori $APP_DIR tidak ditemukan."
    return
  fi
  if ! command -v npm >/dev/null 2>&1; then
    echo "npm tidak ditemukan. Pastikan Node.js dan npm sudah terpasang."
    return
  fi
  cd "$APP_DIR" || return
  echo "Menjalankan npm run build untuk frontend di $APP_DIR ..."
  if npm run build; then
    if command -v pm2 >/dev/null 2>&1; then
      if pm2 list | grep -q "absenta-frontend"; then
        pm2 reload absenta-frontend || echo "Gagal reload proses PM2 absenta-frontend."
      else
        pm2 start "serve -s dist -l 8080" --name absenta-frontend || echo "Gagal start proses PM2 absenta-frontend."
      fi
      pm2 save || true
    fi
  else
    echo "npm run build frontend gagal. Cek log di atas."
  fi
}

reboot_system_menu() {
  echo "PERINGATAN: Sistem akan direboot."
  read -p "Lanjut reboot sekarang? (y/n, default n): " CONFIRM
  CONFIRM=${CONFIRM:-n}
  case "$CONFIRM" in
    y|Y)
      echo "Menjalankan reboot..."
      reboot
      ;;
    *)
      echo "Batal reboot."
      ;;
  esac
}

menu_maintenance() {
  while true; do
    clear
    echo "=== Maintenance & Rebuild ==="
    echo "1. Rebuild Backend (npm run build)"
    echo "2. Rebuild Frontend (npm run build)"
    echo "3. Restart System (reboot)"
    echo "0. Kembali"
    read -p "Pilih: " choice
    case "$choice" in
      1)
        rebuild_backend_app
        pause
        ;;
      2)
        rebuild_frontend_app
        pause
        ;;
      3)
        reboot_system_menu
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

menu_packages() {
  while true; do
    clear
    echo "=== Manajemen Paket Sistem (apt) ==="
    echo "1. Hapus nginx (nginx, nginx-full, nginx-common)"
    echo "2. Hapus Redis (redis-server dan paket terkait)"
    echo "3. Hapus PostgreSQL (postgresql dan paket terkait)"
    echo "4. Jalankan apt autoremove"
    echo "0. Kembali"
    read -p "Pilih: " choice
    case "$choice" in
      1)
        if ! command -v apt-get >/dev/null 2>&1; then
          echo "apt-get tidak ditemukan. Hanya mendukung sistem berbasis Debian/Ubuntu."
          pause
        else
          echo "PERINGATAN: Ini akan menghapus nginx (reverse proxy/web server) dari server ini."
          read -p "Lanjut hapus nginx? (y/n): " CONF
          if [ "$CONF" = "y" ]; then
            apt-get remove --purge -y nginx nginx-full nginx-common || true
            apt-get autoremove -y || true
          else
            echo "Batal hapus nginx."
          fi
          pause
        fi
        ;;
      2)
        if ! command -v apt-get >/dev/null 2>&1; then
          echo "apt-get tidak ditemukan. Hanya mendukung sistem berbasis Debian/Ubuntu."
          pause
        else
          echo "PERINGATAN: Ini akan menghapus Redis server dari server ini."
          read -p "Lanjut hapus redis-server? (y/n): " CONF
          if [ "$CONF" = "y" ]; then
            apt-get remove --purge -y redis-server redis-tools || true
            apt-get autoremove -y || true
          else
            echo "Batal hapus redis-server."
          fi
          pause
        fi
        ;;
      3)
        if ! command -v apt-get >/dev/null 2>&1; then
          echo "apt-get tidak ditemukan. Hanya mendukung sistem berbasis Debian/Ubuntu."
          pause
        else
          echo "PERINGATAN: Ini akan menghapus PostgreSQL server dari server ini."
          echo "Pastikan sudah ada backup database sebelum melanjutkan."
          read -p "Lanjut hapus postgresql? (y/n): " CONF
          if [ "$CONF" = "y" ]; then
            apt-get remove --purge -y 'postgresql*' postgresql-client postgresql-contrib || true
            apt-get autoremove -y || true
          else
            echo "Batal hapus postgresql."
          fi
          pause
        fi
        ;;
      4)
        if ! command -v apt-get >/dev/null 2>&1; then
          echo "apt-get tidak ditemukan."
        else
          apt-get autoremove -y || true
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

menu_deploy() {
  while true; do
    clear
    echo "=== Deploy ==="
    echo "1. Backend + Frontend"
    echo "2. Backend Only"
    echo "3. Frontend Only"
    echo "4. Worker"
    echo "5. Nginx Reverse Proxy"
    echo "6. SSH Server"
    echo "7. WireGuard VPN"
    echo "8. Redis"
    echo "9. PostgreSQL"
    echo "10. Mail Server"
    echo "11. Manajemen Paket"
    echo "0. Kembali"
    read -p "Pilih: " choice
    case "$choice" in
      1)
        menu_app_server
        ;;
      2)
        bash "$SCRIPT_DIR/deploy_backend_server.sh"
        pause
        ;;
      3)
        bash "$SCRIPT_DIR/deploy_frontend_server.sh"
        pause
        ;;
      4)
        menu_worker_server
        ;;
      5)
        menu_nginx
        ;;
      6)
        bash "$SCRIPT_DIR/deploy_ssh_server.sh"
        pause
        ;;
      7)
        menu_wireguard
        ;;
      8)
        menu_redis_server
        ;;
      9)
        menu_db_server
        ;;
      10)
        bash "$SCRIPT_DIR/deploy_mail_server.sh"
        pause
        ;;
      11)
        menu_packages
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

menu_diagnosa() {
  while true; do
    clear
    echo "=== Diagnosa ==="
    echo "1. Diagnos & Report PM2 Backend + Frontend"
    echo "2. Diagnosa PM2 & Monitoring process"
    echo "3. Diagnose WireGuard"
    echo "4. Diagnosa Database"
    echo "5. Diagnosa Nginx"
    echo "6. Diagnosa Redis"
   echo "7. Wizard cek koneksi ke server PostgreSQL"
    echo "0. Kembali"
    read -p "Pilih: " choice
    case "$choice" in
      1)
        diagnose_app_server
        pause
        ;;
      2)
        menu_pm2
        ;;
      3)
        while true; do
          clear
          echo "=== Diagnose WireGuard ==="
          echo "1. Ping"
          echo "2. Run TCP-Dump"
          echo "3. Restart Layanan"
          echo "0. Kembali"
          read -p "Pilih: " wg_choice
          case "$wg_choice" in
            1)
              diagnose_wireguard_ping
              pause
              ;;
            2)
              diagnose_wireguard_tcpdump
              pause
              ;;
            3)
              diagnose_wireguard_restart
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
        pause
        ;;
      4)
        diagnose_db
        pause
        ;;
      5)
        diagnose_nginx
        pause
        ;;
      6)
        diagnose_redis
        pause
        ;;
      7)
        wizard_cek_koneksi_db
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
  echo "===== ABSENTA CONTROL MENU ====="
  echo "1. Deploy"
  echo "2. Diagnosa"
  echo "3. Konfigurasi Environment"
  echo "4. Keamanan Server (Hardening)"
  echo "5. Konfigurasi IP Address"
  echo "6. Maintenance & Rebuild"
  echo "7. PM2 & Monitoring Proses"
  echo "8. Console Backend"
  echo "0. Keluar"
  read -p "Pilih menu: " main_choice
  case "$main_choice" in
    1)
      menu_deploy
      ;;
    2)
      menu_diagnosa
      ;;
    3)
      menu_env_config
      ;;
    4)
      menu_security
      ;;
    5)
      menu_ip_config
      ;;
    6)
      menu_maintenance
      ;;
    7)
      menu_pm2
      ;;
    8)
      backend_console_logs
      pause
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
