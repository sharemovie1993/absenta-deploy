#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${MODE:-}"
COMPOSE_FILE="${COMPOSE_FILE:-}"
ACTION="${ACTION:-deploy}"
if [ -z "${BACKEND_PATH:-}" ]; then
  legacy_backend="$DIR/../../ProjekAbsenta/backend/absenta_backend"
  sibling_backend="$DIR/../absenta_backend"
  if [ -d "$legacy_backend" ]; then
    BACKEND_PATH="$legacy_backend"
  else
    BACKEND_PATH="$sibling_backend"
  fi
fi
BACKEND_REPO="${BACKEND_REPO:-https://github.com/sharemovie1993/absenta_backend.git}"
BACKEND_BRANCH="${BACKEND_BRANCH:-master}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
GITHUB_USERNAME="${GITHUB_USERNAME:-x-access-token}"
NO_CACHE="${NO_CACHE:-false}"
RUN_MIGRATE="${RUN_MIGRATE:-true}"
RUN_SEED="${RUN_SEED:-false}"
STACK_DOWN_FIRST="${STACK_DOWN_FIRST:-true}"
MIGRATE_IMAGE="${MIGRATE_IMAGE:-absenta-backend-migrate:latest}"
SINGLE_STATE_FILE="${SINGLE_STATE_FILE:-/etc/absenta/single.env}"
MULTI_STATE_FILE="${MULTI_STATE_FILE:-/etc/absenta/multi.env}"
BACKUP_STATE_FILE="${BACKUP_STATE_FILE:-/etc/absenta/backup.env}"
TOKEN_GIT_ENV_FILE="${TOKEN_GIT_ENV_FILE:-/etc/absenta/tokengit.env}"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/absenta}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
BACKUP_OFFSITE_METHOD="${BACKUP_OFFSITE_METHOD:-none}"
BACKUP_REMOTE_HOST="${BACKUP_REMOTE_HOST:-}"
BACKUP_REMOTE_USER="${BACKUP_REMOTE_USER:-backup}"
BACKUP_REMOTE_PORT="${BACKUP_REMOTE_PORT:-22}"
BACKUP_REMOTE_DIR="${BACKUP_REMOTE_DIR:-/var/backups/absenta}"
BACKUP_REMOTE_KEY="${BACKUP_REMOTE_KEY:-}"
BACKUP_SMB_SHARE="${BACKUP_SMB_SHARE:-}"
BACKUP_SMB_MOUNT="${BACKUP_SMB_MOUNT:-/mnt/absenta-backup}"
BACKUP_SMB_SUBDIR="${BACKUP_SMB_SUBDIR:-absenta}"
BACKUP_SMB_CREDENTIALS_FILE="${BACKUP_SMB_CREDENTIALS_FILE:-/etc/absenta/smb-backup.cred}"
BACKUP_SMB_DOMAIN="${BACKUP_SMB_DOMAIN:-}"
SSL_ENABLED="${SSL_ENABLED:-}"
DOMAIN="${DOMAIN:-}"
MAIN_DOMAIN="${MAIN_DOMAIN:-}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"
PUBLIC_APP_URL="${PUBLIC_APP_URL:-}"
PUBLIC_INVOICE_BASE_URL="${PUBLIC_INVOICE_BASE_URL:-}"
HTTP_PORT="${HTTP_PORT:-}"
HTTPS_PORT="${HTTPS_PORT:-}"
DEPLOY_FRONTEND="${DEPLOY_FRONTEND:-true}"
FRONTEND_REPO="${FRONTEND_REPO:-https://github.com/sharemovie1993/absenta_frontend.git}"
FRONTEND_BRANCH="${FRONTEND_BRANCH:-master}"
FRONTEND_PATH="${FRONTEND_PATH:-}"
FRONTEND_IMAGE="${FRONTEND_IMAGE:-absenta-frontend:latest}"

# -----------------------------------------------------------------------------
# Ensure dependencies (Ubuntu 22.x friendly). Skip if already installed.
# -----------------------------------------------------------------------------
is_cmd() { command -v "$1" >/dev/null 2>&1; }

apt_update_done=""
apt_ensure() {
  if ! dpkg -s "$1" >/dev/null 2>&1; then
    if [ -z "${apt_update_done}" ]; then
      sudo apt-get update -y
      apt_update_done="yes"
    fi
    sudo apt-get install -y "$@"
  fi
}

ensure_prereqs() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release || true
  fi
  if [ "${ID:-}" = "ubuntu" ]; then
    apt_ensure ca-certificates
    apt_ensure curl
    apt_ensure gnupg
    apt_ensure lsb-release
    apt_ensure git
    apt_ensure iproute2
    apt_ensure openssl
    apt_ensure openssh-client
  fi
}

ensure_docker() {
  if is_cmd docker; then
    return 0
  fi
  if [ "${ID:-}" = "ubuntu" ]; then
    sudo install -m 0755 -d /etc/apt/keyrings
    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      sudo chmod a+r /etc/apt/keyrings/docker.gpg
    fi
    codename="$(. /etc/os-release && echo "$UBUNTU_CODENAME")"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update -y
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    if systemctl >/dev/null 2>&1; then
      sudo systemctl enable --now docker || true
    fi
  else
    echo "Unsupported distro for auto-install. Please install Docker manually."
  fi
}

ensure_prereqs
ensure_docker

# Never prompt for git username/password in non-interactive deploy
export GIT_TERMINAL_PROMPT=0

BACKEND_REPO="$(printf '%s' "$BACKEND_REPO" | tr -d '\r' | xargs)"
BACKEND_REPO="${BACKEND_REPO//\`/}"
BACKEND_REPO="${BACKEND_REPO//\"/}"
BACKEND_REPO="${BACKEND_REPO//\'/}"
BACKEND_REPO="${BACKEND_REPO%/}"

select_main_menu() {
  echo ""
  echo "=== DEPLOY LINUX (ABSENTA) ==="
  echo "1) Deploy/Update SINGLE (1 mesin: nginx+postgres+redis+api+workers)"
  echo "2) Deploy/Update MULTI (DB+Redis external, api+workers di mesin ini)"
  echo "3) Status SINGLE"
  echo "4) Status MULTI"
  echo "5) Logs API"
  echo "6) Restart SINGLE"
  echo "7) Restart MULTI"
  echo "8) Stop SINGLE"
  echo "9) Stop MULTI"
  echo "10) Cleanup disk docker (prune)"
  echo "11) Reset config tersimpan (/etc/absenta/single.env & multi.env)"
  echo "12) Start layanan web VPS (nginx/apache) (kembalikan port 80/443)"
  echo "13) Stop layanan web VPS (nginx/apache)"
  echo "14) Uninstall ABSENTA total (hapus container+volume+image+config+cron)"
  echo "15) Backup SINGLE sekarang (DB+config+SSL)"
  echo "16) Pasang/Update cron backup harian (SINGLE)"
  echo "17) Lihat daftar backup (SINGLE)"
  echo "18) Sync backup SINGLE ke server backup (remote)"
  echo "19) Setup konfigurasi backup (SINGLE) (local+offsite)"
  echo "0) Keluar"
  read -rp "Pilih: " opt
  case "${opt:-}" in
    1) ACTION="deploy"; MODE="single" ;;
    2) ACTION="deploy"; MODE="multi" ;;
    3) ACTION="status"; MODE="single" ;;
    4) ACTION="status"; MODE="multi" ;;
    5) ACTION="logs_api" ;;
    6) ACTION="restart"; MODE="single" ;;
    7) ACTION="restart"; MODE="multi" ;;
    8) ACTION="stop"; MODE="single" ;;
    9) ACTION="stop"; MODE="multi" ;;
    10) ACTION="cleanup" ;;
    11) ACTION="reset_config" ;;
    12) ACTION="start_web" ;;
    13) ACTION="stop_web" ;;
    14) ACTION="uninstall" ;;
    15) ACTION="backup_single"; MODE="single" ;;
    16) ACTION="install_backup_cron"; MODE="single" ;;
    17) ACTION="list_backups"; MODE="single" ;;
    18) ACTION="sync_backups_remote"; MODE="single" ;;
    19) ACTION="setup_backup_remote"; MODE="single" ;;
    0) exit 0 ;;
    *) ACTION="deploy"; MODE="multi" ;;
  esac
}

if [ -z "$MODE" ]; then
  if [ -t 0 ] && [ -t 1 ]; then
    select_main_menu
  else
    MODE="multi"
  fi
fi

if [ -z "$COMPOSE_FILE" ]; then
  case "$MODE" in
    single) COMPOSE_FILE="$DIR/docker-compose.linux.single.yml" ;;
    multi) COMPOSE_FILE="$DIR/docker-compose.linux.multi.yml" ;;
    custom) COMPOSE_FILE="$DIR/docker-compose.linux.yml" ;;
    *) COMPOSE_FILE="$DIR/docker-compose.linux.multi.yml" ;;
  esac
fi

DOCKER_BIN="docker"
if ! docker info >/dev/null 2>&1; then
  if is_cmd sudo && sudo -n true 2>/dev/null; then
    DOCKER_BIN="sudo docker"
  fi
fi
max_wait=180
waited=0
until $DOCKER_BIN info >/dev/null 2>&1; do
  waited=$((waited+5))
  if [ "$waited" -ge "$max_wait" ]; then
    echo "docker engine not ready"
    exit 1
  fi
  sleep 5
done

port_in_use() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "(:|\\.)${port}\$" && return 0
  fi
  return 1
}

ensure_backup_dir() {
  if [ -z "${BACKUP_DIR:-}" ]; then
    echo "BACKUP_DIR belum diset"
    exit 1
  fi
  if is_cmd sudo; then
    sudo mkdir -p "$BACKUP_DIR" >/dev/null 2>&1 || true
    sudo chmod 700 "$BACKUP_DIR" >/dev/null 2>&1 || true
  else
    mkdir -p "$BACKUP_DIR" >/dev/null 2>&1 || true
    chmod 700 "$BACKUP_DIR" >/dev/null 2>&1 || true
  fi
}

offsite_enabled() {
  [ "${BACKUP_OFFSITE_METHOD:-none}" != "none" ]
}

ssh_offsite_enabled() {
  [ "${BACKUP_OFFSITE_METHOD:-none}" = "ssh" ] && [ -n "${BACKUP_REMOTE_HOST:-}" ]
}

smb_offsite_enabled() {
  [ "${BACKUP_OFFSITE_METHOD:-none}" = "smb" ] && [ -n "${BACKUP_SMB_SHARE:-}" ]
}

sync_files_to_ssh() {
  if ! ssh_offsite_enabled; then
    return 0
  fi
  if ! is_cmd ssh || ! is_cmd scp; then
    echo "ssh/scp belum tersedia."
    exit 1
  fi

  local remote="${BACKUP_REMOTE_USER}@${BACKUP_REMOTE_HOST}"
  ssh_args=(
    -p "${BACKUP_REMOTE_PORT}"
    -o StrictHostKeyChecking=accept-new
  )
  scp_args=(
    -P "${BACKUP_REMOTE_PORT}"
    -o StrictHostKeyChecking=accept-new
  )
  if [ -n "${BACKUP_REMOTE_KEY:-}" ]; then
    ssh_args+=(-i "$BACKUP_REMOTE_KEY")
    scp_args+=(-i "$BACKUP_REMOTE_KEY")
  fi

  ssh "${ssh_args[@]}" "$remote" "mkdir -p \"${BACKUP_REMOTE_DIR}\" && chmod 700 \"${BACKUP_REMOTE_DIR}\"" >/dev/null 2>&1 || {
    echo "Gagal membuat folder backup remote (SSH)."
    exit 1
  }

  for f in "$@"; do
    if [ -f "$f" ]; then
      scp "${scp_args[@]}" "$f" "${remote}:${BACKUP_REMOTE_DIR}/" >/dev/null 2>&1 || {
        echo "Gagal upload backup ke remote (SSH)."
        exit 1
      }
    fi
  done
}

smb_mount_share() {
  if ! smb_offsite_enabled; then
    return 0
  fi
  if ! is_cmd sudo; then
    echo "Butuh sudo untuk mount SMB."
    exit 1
  fi
  if [ -f /etc/os-release ]; then
    . /etc/os-release || true
  fi
  if [ "${ID:-}" = "ubuntu" ]; then
    apt_ensure cifs-utils
  fi

  sudo mkdir -p "$BACKUP_SMB_MOUNT" >/dev/null 2>&1 || true
  sudo chmod 700 "$BACKUP_SMB_MOUNT" >/dev/null 2>&1 || true

  if is_cmd mountpoint; then
    if mountpoint -q "$BACKUP_SMB_MOUNT"; then
      return 0
    fi
  else
    if grep -q " $BACKUP_SMB_MOUNT " /proc/mounts 2>/dev/null; then
      return 0
    fi
  fi

  if [ ! -f "$BACKUP_SMB_CREDENTIALS_FILE" ]; then
    echo "Credentials SMB tidak ditemukan: $BACKUP_SMB_CREDENTIALS_FILE"
    exit 1
  fi

  smb_opts="credentials=${BACKUP_SMB_CREDENTIALS_FILE},iocharset=utf8,vers=3.0,file_mode=0600,dir_mode=0700,noperm"
  if [ -n "${BACKUP_SMB_DOMAIN:-}" ]; then
    smb_opts="${smb_opts},domain=${BACKUP_SMB_DOMAIN}"
  fi

  sudo mount -t cifs "$BACKUP_SMB_SHARE" "$BACKUP_SMB_MOUNT" -o "$smb_opts" >/dev/null 2>&1 || {
    echo "Gagal mount SMB share."
    exit 1
  }
}

sync_files_to_smb() {
  if ! smb_offsite_enabled; then
    return 0
  fi
  smb_mount_share

  sudo mkdir -p "$BACKUP_SMB_MOUNT/$BACKUP_SMB_SUBDIR" >/dev/null 2>&1 || true
  sudo chmod 700 "$BACKUP_SMB_MOUNT/$BACKUP_SMB_SUBDIR" >/dev/null 2>&1 || true

  for f in "$@"; do
    if [ -f "$f" ]; then
      sudo cp -f "$f" "$BACKUP_SMB_MOUNT/$BACKUP_SMB_SUBDIR/" >/dev/null 2>&1 || {
        echo "Gagal copy backup ke SMB."
        exit 1
      }
      sudo chmod 600 "$BACKUP_SMB_MOUNT/$BACKUP_SMB_SUBDIR/$(basename "$f")" >/dev/null 2>&1 || true
    fi
  done
}

sync_files_offsite() {
  if ! offsite_enabled; then
    return 0
  fi
  case "${BACKUP_OFFSITE_METHOD:-none}" in
    ssh) sync_files_to_ssh "$@" ;;
    smb) sync_files_to_smb "$@" ;;
    *) return 0 ;;
  esac
}

sync_all_backups_to_remote() {
  if ! offsite_enabled; then
    echo "Backup offsite belum diaktifkan."
    exit 1
  fi
  if [ "${BACKUP_OFFSITE_METHOD:-none}" = "ssh" ] && [ -z "${BACKUP_REMOTE_HOST:-}" ]; then
    echo "BACKUP_REMOTE_HOST belum diset."
    exit 1
  fi
  if [ "${BACKUP_OFFSITE_METHOD:-none}" = "smb" ] && [ -z "${BACKUP_SMB_SHARE:-}" ]; then
    echo "BACKUP_SMB_SHARE belum diset."
    exit 1
  fi

  ensure_backup_dir
  files=()
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find "$BACKUP_DIR" -maxdepth 1 -type f -name "absenta-*" -print0 2>/dev/null || true)

  if [ "${#files[@]}" -eq 0 ]; then
    echo "Tidak ada file backup untuk disync."
    exit 0
  fi
  sync_files_offsite "${files[@]}"
  echo "Sync backup offsite selesai."
}

setup_backup_remote() {
  if [ "$MODE" != "single" ]; then
    echo "Setup backup remote ini hanya untuk MODE=single"
    exit 1
  fi
  if ! is_cmd sudo; then
    echo "Butuh sudo untuk menyimpan konfigurasi backup."
    exit 1
  fi
  if ! ( [ -t 0 ] && [ -t 1 ] ); then
    echo "Setup backup remote butuh mode interaktif."
    exit 1
  fi

  read -rp "BACKUP_DIR [${BACKUP_DIR}]: " v
  BACKUP_DIR="${v:-$BACKUP_DIR}"
  read -rp "BACKUP_RETENTION_DAYS [${BACKUP_RETENTION_DAYS}]: " v
  BACKUP_RETENTION_DAYS="${v:-$BACKUP_RETENTION_DAYS}"

  echo ""
  echo "Pilih metode backup offsite:"
  echo "  0) Nonaktif"
  echo "  1) SSH/SCP (Linux server) (butuh SSH key untuk cron)"
  echo "  2) SMB (Windows share/NAS) (pakai username+password)"
  read -rp "Metode [0/1/2]: " m
  case "${m:-}" in
    1) BACKUP_OFFSITE_METHOD="ssh" ;;
    2) BACKUP_OFFSITE_METHOD="smb" ;;
    *) BACKUP_OFFSITE_METHOD="none" ;;
  esac

  if [ "$BACKUP_OFFSITE_METHOD" = "ssh" ]; then
    read -rp "SSH: IP/Host server backup (contoh: 10.10.10.10) [${BACKUP_REMOTE_HOST}]: " v
    BACKUP_REMOTE_HOST="${v:-$BACKUP_REMOTE_HOST}"
    read -rp "SSH: User login [${BACKUP_REMOTE_USER}]: " v
    BACKUP_REMOTE_USER="${v:-$BACKUP_REMOTE_USER}"
    read -rp "SSH: Port [${BACKUP_REMOTE_PORT}]: " v
    BACKUP_REMOTE_PORT="${v:-$BACKUP_REMOTE_PORT}"
    read -rp "SSH: Folder tujuan di server backup [${BACKUP_REMOTE_DIR}]: " v
    BACKUP_REMOTE_DIR="${v:-$BACKUP_REMOTE_DIR}"
    read -rp "SSH: Path private key (kosong=pakai default ~/.ssh) [${BACKUP_REMOTE_KEY}]: " v
    BACKUP_REMOTE_KEY="${v:-$BACKUP_REMOTE_KEY}"
  fi

  if [ "$BACKUP_OFFSITE_METHOD" = "smb" ]; then
    read -rp "SMB: Share (contoh: //10.10.10.10/backup) (tanpa subfolder) [${BACKUP_SMB_SHARE}]: " v
    BACKUP_SMB_SHARE="${v:-$BACKUP_SMB_SHARE}"
    read -rp "SMB: Folder tujuan di dalam share [${BACKUP_SMB_SUBDIR}]: " v
    BACKUP_SMB_SUBDIR="${v:-$BACKUP_SMB_SUBDIR}"
    read -rp "SMB: Domain (opsional, kosong jika tidak ada) [${BACKUP_SMB_DOMAIN}]: " v
    BACKUP_SMB_DOMAIN="${v:-$BACKUP_SMB_DOMAIN}"
    read -rp "SMB: Username [backup]: " v
    smb_user="${v:-backup}"
    read -rsp "SMB: Password (tidak akan tampil): " smb_pass
    echo ""
    read -rp "SMB: Simpan credentials ke file [${BACKUP_SMB_CREDENTIALS_FILE}]: " v
    BACKUP_SMB_CREDENTIALS_FILE="${v:-$BACKUP_SMB_CREDENTIALS_FILE}"

    sudo mkdir -p "$(dirname "$BACKUP_SMB_CREDENTIALS_FILE")" >/dev/null 2>&1 || true
    tmp_cred="/tmp/absenta-smb-cred.$$"
    umask 077
    {
      echo "username=${smb_user}"
      echo "password=${smb_pass}"
    } > "$tmp_cred"
    sudo mv "$tmp_cred" "$BACKUP_SMB_CREDENTIALS_FILE" >/dev/null 2>&1 || true
    sudo chmod 600 "$BACKUP_SMB_CREDENTIALS_FILE" >/dev/null 2>&1 || true
  fi

  export BACKUP_DIR BACKUP_RETENTION_DAYS BACKUP_OFFSITE_METHOD BACKUP_REMOTE_HOST BACKUP_REMOTE_USER BACKUP_REMOTE_PORT BACKUP_REMOTE_DIR BACKUP_REMOTE_KEY BACKUP_SMB_SHARE BACKUP_SMB_MOUNT BACKUP_SMB_SUBDIR BACKUP_SMB_CREDENTIALS_FILE BACKUP_SMB_DOMAIN
  save_backup_state
  echo "Setup backup remote tersimpan: $BACKUP_STATE_FILE"
}

backup_single() {
  if [ "$MODE" != "single" ]; then
    echo "Backup ini hanya untuk MODE=single"
    exit 1
  fi
  ensure_backup_dir

  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"

  local tmp_db="/tmp/absenta-db-${stamp}.sql.gz"
  local tmp_cfg="/tmp/absenta-config-${stamp}.tar.gz"
  local tmp_ssl="/tmp/absenta-letsencrypt-${stamp}.tar.gz"
  umask 077

  if [ -f "$SINGLE_STATE_FILE" ]; then
    set -a
    . "$SINGLE_STATE_FILE" || true
    set +a
  fi
  POSTGRES_DB="${POSTGRES_DB:-absensi}"
  POSTGRES_USER="${POSTGRES_USER:-postgres}"
  POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-}"

  $DOCKER_BIN compose -f "$COMPOSE_FILE" up -d postgres >/dev/null 2>&1 || true

  if $DOCKER_BIN ps --format "{{.Names}}" | grep -qx "absenta-postgres"; then
    $DOCKER_BIN exec -e PGPASSWORD="$POSTGRES_PASSWORD" absenta-postgres \
      pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" | gzip -c > "$tmp_db"
  else
    echo "Container absenta-postgres tidak ditemukan."
    exit 1
  fi

  if is_cmd sudo; then
    sudo tar -czf "$tmp_cfg" \
      /etc/absenta/single.env \
      /etc/absenta/multi.env \
      /etc/absenta/backup.env \
      /etc/absenta/tokengit.env \
      /etc/absenta/smb-backup.cred \
      /etc/cron.d/absenta-certbot \
      /etc/cron.d/absenta-backup >/dev/null 2>&1 || true
  else
    tar -czf "$tmp_cfg" \
      /etc/absenta/single.env \
      /etc/absenta/multi.env \
      /etc/absenta/backup.env \
      /etc/absenta/tokengit.env \
      /etc/absenta/smb-backup.cred \
      /etc/cron.d/absenta-certbot \
      /etc/cron.d/absenta-backup >/dev/null 2>&1 || true
  fi

  if $DOCKER_BIN volume ls --format "{{.Name}}" | grep -qx "absenta-letsencrypt"; then
    $DOCKER_BIN run --rm -v absenta-letsencrypt:/data -v /tmp:/backup bash:5 \
      tar -czf "/backup/$(basename "$tmp_ssl")" -C /data . >/dev/null 2>&1 || true
  fi

  if is_cmd sudo; then
    sudo mv -f "$tmp_db" "$BACKUP_DIR/" >/dev/null 2>&1 || true
    sudo mv -f "$tmp_cfg" "$BACKUP_DIR/" >/dev/null 2>&1 || true
    if [ -f "$tmp_ssl" ]; then
      sudo mv -f "$tmp_ssl" "$BACKUP_DIR/" >/dev/null 2>&1 || true
    fi
    sudo chmod 600 "$BACKUP_DIR/$(basename "$tmp_db")" "$BACKUP_DIR/$(basename "$tmp_cfg")" >/dev/null 2>&1 || true
    if [ -f "$BACKUP_DIR/$(basename "$tmp_ssl")" ]; then
      sudo chmod 600 "$BACKUP_DIR/$(basename "$tmp_ssl")" >/dev/null 2>&1 || true
    fi
  else
    mv -f "$tmp_db" "$BACKUP_DIR/" >/dev/null 2>&1 || true
    mv -f "$tmp_cfg" "$BACKUP_DIR/" >/dev/null 2>&1 || true
    if [ -f "$tmp_ssl" ]; then
      mv -f "$tmp_ssl" "$BACKUP_DIR/" >/dev/null 2>&1 || true
    fi
    chmod 600 "$BACKUP_DIR/$(basename "$tmp_db")" "$BACKUP_DIR/$(basename "$tmp_cfg")" >/dev/null 2>&1 || true
    if [ -f "$BACKUP_DIR/$(basename "$tmp_ssl")" ]; then
      chmod 600 "$BACKUP_DIR/$(basename "$tmp_ssl")" >/dev/null 2>&1 || true
    fi
  fi

  synced_files=(
    "$BACKUP_DIR/$(basename "$tmp_db")"
    "$BACKUP_DIR/$(basename "$tmp_cfg")"
  )
  if [ -f "$BACKUP_DIR/$(basename "$tmp_ssl")" ]; then
    synced_files+=("$BACKUP_DIR/$(basename "$tmp_ssl")")
  fi
  sync_files_offsite "${synced_files[@]}"

  if [ -n "${BACKUP_RETENTION_DAYS:-}" ]; then
    if is_cmd sudo; then
      sudo find "$BACKUP_DIR" -type f -name "absenta-*" -mtime +"$BACKUP_RETENTION_DAYS" -delete >/dev/null 2>&1 || true
    else
      find "$BACKUP_DIR" -type f -name "absenta-*" -mtime +"$BACKUP_RETENTION_DAYS" -delete >/dev/null 2>&1 || true
    fi
  fi

  echo "Backup selesai: $BACKUP_DIR"
}

install_backup_cron() {
  if [ "$MODE" != "single" ]; then
    echo "Cron backup ini hanya untuk MODE=single"
    exit 1
  fi
  if ! is_cmd sudo; then
    echo "Butuh sudo untuk pasang cron backup."
    exit 1
  fi
  sudo apt-get update -y >/dev/null 2>&1 || true
  sudo apt-get install -y cron >/dev/null 2>&1 || true

  ensure_backup_dir
  local script_path
  script_path="$DIR/$(basename "$0")"

  cat <<EOF | sudo tee /etc/cron.d/absenta-backup >/dev/null
SHELL=/bin/bash
PATH=/usr/sbin:/usr/bin:/sbin:/bin
30 2 * * * root MODE=single ACTION=backup_single BACKUP_DIR=${BACKUP_DIR} BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS} BACKUP_OFFSITE_METHOD=${BACKUP_OFFSITE_METHOD} BACKUP_REMOTE_HOST=${BACKUP_REMOTE_HOST} BACKUP_REMOTE_USER=${BACKUP_REMOTE_USER} BACKUP_REMOTE_PORT=${BACKUP_REMOTE_PORT} BACKUP_REMOTE_DIR=${BACKUP_REMOTE_DIR} BACKUP_REMOTE_KEY=${BACKUP_REMOTE_KEY} BACKUP_SMB_SHARE=${BACKUP_SMB_SHARE} BACKUP_SMB_MOUNT=${BACKUP_SMB_MOUNT} BACKUP_SMB_SUBDIR=${BACKUP_SMB_SUBDIR} BACKUP_SMB_CREDENTIALS_FILE=${BACKUP_SMB_CREDENTIALS_FILE} BACKUP_SMB_DOMAIN=${BACKUP_SMB_DOMAIN} /usr/bin/env bash ${script_path} >/var/log/absenta-backup.log 2>&1
EOF
  sudo chmod 644 /etc/cron.d/absenta-backup >/dev/null 2>&1 || true
  sudo systemctl enable --now cron >/dev/null 2>&1 || true
  echo "Cron backup terpasang: /etc/cron.d/absenta-backup"
}

list_backups() {
  if [ "$MODE" != "single" ]; then
    echo "List backup ini hanya untuk MODE=single"
    exit 1
  fi
  ensure_backup_dir
  if is_cmd sudo; then
    sudo ls -lah "$BACKUP_DIR" | tail -n +1
  else
    ls -lah "$BACKUP_DIR" | tail -n +1
  fi
}

prompt_ports() {
  if [ -z "${HTTP_PORT:-}" ]; then
    HTTP_PORT="80"
  fi
  if [ -z "${HTTPS_PORT:-}" ]; then
    HTTPS_PORT="443"
  fi

  if port_in_use "$HTTP_PORT" || port_in_use "$HTTPS_PORT"; then
    echo "Port ${HTTP_PORT} atau ${HTTPS_PORT} sedang dipakai service lain."
    echo "Pilih solusi:"
    echo "  1) Stop nginx/apache di VPS (jika ada) lalu pakai 80/443"
    echo "  2) Pakai port alternatif (misal 8080/8443)"
    read -rp "Pilihan [1/2]: " psel
    if [ "${psel:-}" = "1" ]; then
      if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl stop nginx 2>/dev/null || true
        sudo systemctl stop apache2 2>/dev/null || true
        sudo systemctl stop httpd 2>/dev/null || true
      fi
    else
      read -rp "HTTP_PORT [8080]: " HTTP_PORT
      HTTP_PORT="${HTTP_PORT:-8080}"
      read -rp "HTTPS_PORT [8443]: " HTTPS_PORT
      HTTPS_PORT="${HTTPS_PORT:-8443}"
    fi
  fi
  export HTTP_PORT HTTPS_PORT
}

run_non_deploy_action() {
  case "$ACTION" in
    status)
      $DOCKER_BIN compose -f "$COMPOSE_FILE" ps || true
      $DOCKER_BIN ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" || true
      exit 0
      ;;
    logs_api)
      $DOCKER_BIN logs --tail 200 -f absenta-backend-api
      exit 0
      ;;
    restart)
      $DOCKER_BIN compose -f "$COMPOSE_FILE" restart
      exit 0
      ;;
    stop)
      $DOCKER_BIN compose -f "$COMPOSE_FILE" down || true
      exit 0
      ;;
    cleanup)
      $DOCKER_BIN system prune -af --volumes
      $DOCKER_BIN builder prune -af
      exit 0
      ;;
    reset_config)
      if is_cmd sudo; then
        sudo rm -f /etc/absenta/single.env /etc/absenta/multi.env /etc/absenta/backup.env || true
      else
        rm -f /etc/absenta/single.env /etc/absenta/multi.env /etc/absenta/backup.env || true
      fi
      echo "Config reset OK"
      exit 0
      ;;
    start_web)
      if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl start nginx 2>/dev/null || true
        sudo systemctl start apache2 2>/dev/null || true
        sudo systemctl start httpd 2>/dev/null || true
      fi
      echo "Layanan web VPS (jika ada) sudah dicoba dijalankan."
      exit 0
      ;;
    stop_web)
      if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl stop nginx 2>/dev/null || true
        sudo systemctl stop apache2 2>/dev/null || true
        sudo systemctl stop httpd 2>/dev/null || true
      fi
      echo "Layanan web VPS (jika ada) sudah dicoba dihentikan."
      exit 0
      ;;
    uninstall)
      single_compose="$DIR/docker-compose.linux.single.yml"
      multi_compose="$DIR/docker-compose.linux.multi.yml"
      $DOCKER_BIN compose -f "$single_compose" down -v --remove-orphans >/dev/null 2>&1 || true
      $DOCKER_BIN compose -f "$multi_compose" down -v --remove-orphans >/dev/null 2>&1 || true

      $DOCKER_BIN rm -f absenta-nginx absenta-frontend absenta-backend-api absenta-postgres absenta-redis >/dev/null 2>&1 || true
      $DOCKER_BIN ps -a --format "{{.Names}}" | grep -E '^absenta-' | xargs -r $DOCKER_BIN rm -f >/dev/null 2>&1 || true

      $DOCKER_BIN image rm -f absenta-backend:latest absenta-backend-migrate:latest absenta-frontend:latest >/dev/null 2>&1 || true

      $DOCKER_BIN volume rm -f absenta_pgdata absenta_redisdata absenta-letsencrypt absenta-certbot-www >/dev/null 2>&1 || true
      $DOCKER_BIN network rm absenta-net >/dev/null 2>&1 || true

      if is_cmd sudo; then
        sudo rm -f /etc/absenta/single.env /etc/absenta/multi.env /etc/absenta/backup.env /etc/absenta/github.token /etc/absenta/tokengit.env /etc/absenta/smb-backup.cred /etc/cron.d/absenta-certbot /etc/cron.d/absenta-backup >/dev/null 2>&1 || true
      else
        rm -f /etc/absenta/single.env /etc/absenta/multi.env /etc/absenta/backup.env /etc/absenta/github.token /etc/absenta/tokengit.env /etc/absenta/smb-backup.cred /etc/cron.d/absenta-certbot /etc/cron.d/absenta-backup >/dev/null 2>&1 || true
      fi
      rm -f "$DIR/../env/.env.tokengit" >/dev/null 2>&1 || true

      if [ -d "$DIR/../absenta_backend/.git" ]; then
        rm -rf "$DIR/../absenta_backend" >/dev/null 2>&1 || true
      fi
      if [ -d "$DIR/../absenta_frontend/.git" ]; then
        rm -rf "$DIR/../absenta_frontend" >/dev/null 2>&1 || true
      fi

      echo "Uninstall ABSENTA selesai."
      exit 0
      ;;
    backup_single)
      backup_single
      exit 0
      ;;
    install_backup_cron)
      install_backup_cron
      exit 0
      ;;
    list_backups)
      list_backups
      exit 0
      ;;
    sync_backups_remote)
      sync_all_backups_to_remote
      exit 0
      ;;
    setup_backup_remote)
      setup_backup_remote
      exit 0
      ;;
  esac
}

load_backup_state() {
  if [ -f "$BACKUP_STATE_FILE" ]; then
    set -a
    . "$BACKUP_STATE_FILE" || true
    set +a
  fi
  BACKUP_DIR="$(printf '%s' "${BACKUP_DIR:-}" | tr -d '\r' | xargs)"
  BACKUP_REMOTE_HOST="$(printf '%s' "${BACKUP_REMOTE_HOST:-}" | tr -d '\r' | xargs)"
  BACKUP_REMOTE_USER="$(printf '%s' "${BACKUP_REMOTE_USER:-}" | tr -d '\r' | xargs)"
  BACKUP_REMOTE_PORT="$(printf '%s' "${BACKUP_REMOTE_PORT:-}" | tr -d '\r' | xargs)"
  BACKUP_REMOTE_DIR="$(printf '%s' "${BACKUP_REMOTE_DIR:-}" | tr -d '\r' | xargs)"
  BACKUP_REMOTE_KEY="$(printf '%s' "${BACKUP_REMOTE_KEY:-}" | tr -d '\r' | xargs)"
  BACKUP_RETENTION_DAYS="$(printf '%s' "${BACKUP_RETENTION_DAYS:-}" | tr -d '\r' | xargs)"
  BACKUP_OFFSITE_METHOD="$(printf '%s' "${BACKUP_OFFSITE_METHOD:-}" | tr -d '\r' | xargs)"
  BACKUP_SMB_SHARE="$(printf '%s' "${BACKUP_SMB_SHARE:-}" | tr -d '\r' | xargs)"
  BACKUP_SMB_MOUNT="$(printf '%s' "${BACKUP_SMB_MOUNT:-}" | tr -d '\r' | xargs)"
  BACKUP_SMB_SUBDIR="$(printf '%s' "${BACKUP_SMB_SUBDIR:-}" | tr -d '\r' | xargs)"
  BACKUP_SMB_CREDENTIALS_FILE="$(printf '%s' "${BACKUP_SMB_CREDENTIALS_FILE:-}" | tr -d '\r' | xargs)"
  BACKUP_SMB_DOMAIN="$(printf '%s' "${BACKUP_SMB_DOMAIN:-}" | tr -d '\r' | xargs)"
}

save_backup_state() {
  if ! is_cmd sudo; then
    return 0
  fi
  sudo mkdir -p "$(dirname "$BACKUP_STATE_FILE")" >/dev/null 2>&1 || true
  tmp_state="/tmp/absenta-backup.env.$$"
  umask 077
  {
    echo "BACKUP_DIR=${BACKUP_DIR:-}"
    echo "BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-}"
    echo "BACKUP_OFFSITE_METHOD=${BACKUP_OFFSITE_METHOD:-none}"
    echo "BACKUP_REMOTE_HOST=${BACKUP_REMOTE_HOST:-}"
    echo "BACKUP_REMOTE_USER=${BACKUP_REMOTE_USER:-}"
    echo "BACKUP_REMOTE_PORT=${BACKUP_REMOTE_PORT:-}"
    echo "BACKUP_REMOTE_DIR=${BACKUP_REMOTE_DIR:-}"
    echo "BACKUP_REMOTE_KEY=${BACKUP_REMOTE_KEY:-}"
    echo "BACKUP_SMB_SHARE=${BACKUP_SMB_SHARE:-}"
    echo "BACKUP_SMB_MOUNT=${BACKUP_SMB_MOUNT:-}"
    echo "BACKUP_SMB_SUBDIR=${BACKUP_SMB_SUBDIR:-}"
    echo "BACKUP_SMB_CREDENTIALS_FILE=${BACKUP_SMB_CREDENTIALS_FILE:-}"
    echo "BACKUP_SMB_DOMAIN=${BACKUP_SMB_DOMAIN:-}"
  } > "$tmp_state"
  sudo mv "$tmp_state" "$BACKUP_STATE_FILE" >/dev/null 2>&1 || true
  sudo chmod 600 "$BACKUP_STATE_FILE" >/dev/null 2>&1 || true
}

if [ "$ACTION" != "deploy" ]; then
  load_backup_state
  run_non_deploy_action
fi

load_single_state() {
  if [ "$MODE" != "single" ]; then
    return 0
  fi
  if [ -f "$SINGLE_STATE_FILE" ]; then
    set -a
    . "$SINGLE_STATE_FILE" || true
    set +a
  fi
  PUBLIC_APP_URL="${PUBLIC_APP_URL//\`/}"
  PUBLIC_APP_URL="${PUBLIC_APP_URL//\"/}"
  PUBLIC_APP_URL="${PUBLIC_APP_URL//\'/}"
  PUBLIC_APP_URL="$(printf '%s' "$PUBLIC_APP_URL" | tr -d '\r' | xargs)"
  PUBLIC_INVOICE_BASE_URL="${PUBLIC_INVOICE_BASE_URL//\`/}"
  PUBLIC_INVOICE_BASE_URL="${PUBLIC_INVOICE_BASE_URL//\"/}"
  PUBLIC_INVOICE_BASE_URL="${PUBLIC_INVOICE_BASE_URL//\'/}"
  PUBLIC_INVOICE_BASE_URL="$(printf '%s' "$PUBLIC_INVOICE_BASE_URL" | tr -d '\r' | xargs)"
  MAIN_DOMAIN="${MAIN_DOMAIN//\`/}"
  MAIN_DOMAIN="${MAIN_DOMAIN//\"/}"
  MAIN_DOMAIN="${MAIN_DOMAIN//\'/}"
  MAIN_DOMAIN="$(printf '%s' "$MAIN_DOMAIN" | tr -d '\r' | xargs)"
}

load_multi_state() {
  if [ "$MODE" != "multi" ]; then
    return 0
  fi
  if [ -f "$MULTI_STATE_FILE" ]; then
    set -a
    . "$MULTI_STATE_FILE" || true
    set +a
  fi
  PUBLIC_APP_URL="${PUBLIC_APP_URL//\`/}"
  PUBLIC_APP_URL="${PUBLIC_APP_URL//\"/}"
  PUBLIC_APP_URL="${PUBLIC_APP_URL//\'/}"
  PUBLIC_APP_URL="$(printf '%s' "$PUBLIC_APP_URL" | tr -d '\r' | xargs)"
  PUBLIC_INVOICE_BASE_URL="${PUBLIC_INVOICE_BASE_URL//\`/}"
  PUBLIC_INVOICE_BASE_URL="${PUBLIC_INVOICE_BASE_URL//\"/}"
  PUBLIC_INVOICE_BASE_URL="${PUBLIC_INVOICE_BASE_URL//\'/}"
  PUBLIC_INVOICE_BASE_URL="$(printf '%s' "$PUBLIC_INVOICE_BASE_URL" | tr -d '\r' | xargs)"
  MAIN_DOMAIN="${MAIN_DOMAIN//\`/}"
  MAIN_DOMAIN="${MAIN_DOMAIN//\"/}"
  MAIN_DOMAIN="${MAIN_DOMAIN//\'/}"
  MAIN_DOMAIN="$(printf '%s' "$MAIN_DOMAIN" | tr -d '\r' | xargs)"
}

save_single_state() {
  if [ "$MODE" != "single" ]; then
    return 0
  fi
  if ! is_cmd sudo; then
    return 0
  fi
  sudo mkdir -p "$(dirname "$SINGLE_STATE_FILE")" >/dev/null 2>&1 || true
  tmp_state="/tmp/absenta-single.env.$$"
  umask 077
  {
    echo "POSTGRES_DB=${POSTGRES_DB:-absensi}"
    echo "POSTGRES_USER=${POSTGRES_USER:-postgres}"
    echo "POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-}"
    echo "DOMAIN=${DOMAIN:-}"
    echo "MAIN_DOMAIN=${MAIN_DOMAIN:-}"
    echo "CERTBOT_EMAIL=${CERTBOT_EMAIL:-}"
    echo "SSL_ENABLED=${SSL_ENABLED:-}"
    echo "PUBLIC_APP_URL=${PUBLIC_APP_URL:-}"
    echo "PUBLIC_INVOICE_BASE_URL=${PUBLIC_INVOICE_BASE_URL:-}"
    echo "HTTP_PORT=${HTTP_PORT:-}"
    echo "HTTPS_PORT=${HTTPS_PORT:-}"
    echo "DEPLOY_FRONTEND=${DEPLOY_FRONTEND:-}"
    echo "FRONTEND_REPO=${FRONTEND_REPO:-}"
    echo "FRONTEND_BRANCH=${FRONTEND_BRANCH:-}"
  } > "$tmp_state"
  sudo mv "$tmp_state" "$SINGLE_STATE_FILE" >/dev/null 2>&1 || true
  sudo chmod 600 "$SINGLE_STATE_FILE" >/dev/null 2>&1 || true
}

save_multi_state() {
  if [ "$MODE" != "multi" ]; then
    return 0
  fi
  if ! is_cmd sudo; then
    return 0
  fi
  sudo mkdir -p "$(dirname "$MULTI_STATE_FILE")" >/dev/null 2>&1 || true
  tmp_state="/tmp/absenta-multi.env.$$"
  umask 077
  {
    echo "DATABASE_URL=${DATABASE_URL:-}"
    echo "REDIS_URL=${REDIS_URL:-}"
    echo "PUBLIC_APP_URL=${PUBLIC_APP_URL:-}"
    echo "PUBLIC_INVOICE_BASE_URL=${PUBLIC_INVOICE_BASE_URL:-}"
    echo "HTTP_PORT=${HTTP_PORT:-}"
    echo "HTTPS_PORT=${HTTPS_PORT:-}"
    echo "SSL_ENABLED=${SSL_ENABLED:-}"
    echo "DOMAIN=${DOMAIN:-}"
    echo "MAIN_DOMAIN=${MAIN_DOMAIN:-}"
    echo "CERTBOT_EMAIL=${CERTBOT_EMAIL:-}"
    echo "DEPLOY_FRONTEND=${DEPLOY_FRONTEND:-}"
    echo "FRONTEND_REPO=${FRONTEND_REPO:-}"
    echo "FRONTEND_BRANCH=${FRONTEND_BRANCH:-}"
  } > "$tmp_state"
  sudo mv "$tmp_state" "$MULTI_STATE_FILE" >/dev/null 2>&1 || true
  sudo chmod 600 "$MULTI_STATE_FILE" >/dev/null 2>&1 || true
}

load_single_state
load_multi_state
load_backup_state

if [ -t 0 ] && [ -t 1 ]; then
  prompt_ports
fi

prompt_github_token() {
  if [ -z "${GITHUB_USERNAME:-}" ]; then
    GITHUB_USERNAME="x-access-token"
  fi
  if [ -z "${GITHUB_TOKEN:-}" ] && [ -f "${TOKEN_GIT_ENV_FILE:-}" ]; then
    tokLine="$(grep -E '^[[:space:]]*TOKEN_GIT=' "$TOKEN_GIT_ENV_FILE" | tail -n 1 || true)"
    if [ -n "${tokLine:-}" ]; then
      GITHUB_TOKEN="${tokLine#*=}"
      GITHUB_TOKEN="$(printf '%s' "$GITHUB_TOKEN" | tr -d '\r' | xargs)"
      GITHUB_TOKEN="${GITHUB_TOKEN#\"}"; GITHUB_TOKEN="${GITHUB_TOKEN%\"}"
      GITHUB_TOKEN="${GITHUB_TOKEN#\'}"; GITHUB_TOKEN="${GITHUB_TOKEN%\'}"
    fi
  fi
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    if [ -t 0 ] && [ -t 1 ]; then
      read -rsp "Masukkan GitHub Token (boleh kosong untuk repo publik): " GITHUB_TOKEN
      echo ""
      GITHUB_TOKEN="$(printf '%s' "${GITHUB_TOKEN:-}" | tr -d '\r' | xargs)"
    else
      : "${GITHUB_TOKEN:=}"
    fi
  fi
  export GITHUB_USERNAME GITHUB_TOKEN
}

build_git_auth_args() {
  local token="$1"
  local username="$2"
  if [ -z "${token:-}" ]; then
    return 0
  fi
  if ! is_cmd base64; then
    echo "base64 belum tersedia. Instal dulu: sudo apt-get update && sudo apt-get install -y coreutils"
    exit 1
  fi
  local basic
  basic="$(printf '%s:%s' "${username:-x-access-token}" "$token" | base64 | tr -d '\n')"
  git_auth_args+=(-c "http.https://github.com/.extraheader=AUTHORIZATION: basic ${basic}")
}
prompt_github_token

prompt_db_redis() {
  if [ "$MODE" = "single" ]; then
    if [ -z "${POSTGRES_DB:-}" ]; then
      read -rp "POSTGRES_DB [absensi]: " POSTGRES_DB
      POSTGRES_DB="${POSTGRES_DB:-absensi}"
    fi
    if [ -z "${POSTGRES_USER:-}" ]; then
      read -rp "POSTGRES_USER [postgres]: " POSTGRES_USER
      POSTGRES_USER="${POSTGRES_USER:-postgres}"
    fi
    if [ -z "${POSTGRES_PASSWORD:-}" ]; then
      read -rsp "POSTGRES_PASSWORD (tidak akan tampil): " POSTGRES_PASSWORD
      echo ""
      if [ -z "$POSTGRES_PASSWORD" ]; then
        if is_cmd openssl; then
          POSTGRES_PASSWORD="$(openssl rand -hex 24)"
        else
          POSTGRES_PASSWORD="change-me"
        fi
      fi
    fi
    if [ -z "${DATABASE_URL:-}" ]; then
      DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}"
    fi
    if [ -z "${REDIS_URL:-}" ]; then
      REDIS_URL="redis://redis:6379"
    fi
  else
    if [ -z "${DATABASE_URL:-}" ]; then
      read -rp "DB_HOST (contoh: 10.10.10.250): " DB_HOST
      read -rp "DB_PORT [5432]: " DB_PORT
      DB_PORT="${DB_PORT:-5432}"
      read -rp "DB_NAME [absensi]: " DB_NAME
      DB_NAME="${DB_NAME:-absensi}"
      read -rp "DB_USER [postgres]: " DB_USER
      DB_USER="${DB_USER:-postgres}"
      read -rsp "DB_PASSWORD (tidak akan tampil): " DB_PASSWORD
      echo ""
      DATABASE_URL="postgresql://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
    fi
    if [ -z "${REDIS_URL:-}" ]; then
      read -rp "REDIS_URL (contoh: redis://10.10.10.250:6379): " REDIS_URL
    fi
  fi
  export DATABASE_URL REDIS_URL POSTGRES_DB POSTGRES_USER POSTGRES_PASSWORD PUBLIC_APP_URL PUBLIC_INVOICE_BASE_URL
}

if [ -t 0 ] && [ -t 1 ]; then
  prompt_db_redis
else
  : "${DATABASE_URL:=}"
  : "${REDIS_URL:=}"
fi

prompt_ssl_single() {
  if [ "$MODE" != "single" ] && [ "$MODE" != "multi" ]; then
    return 0
  fi
  if [ -z "$SSL_ENABLED" ]; then
    read -rp "Aktifkan SSL (HTTPS) + domain? [y/N]: " ans
    case "$(printf '%s' "${ans:-}" | tr '[:upper:]' '[:lower:]')" in
      y|yes) SSL_ENABLED="true" ;;
      *) SSL_ENABLED="false" ;;
    esac
  fi
  if [ "$SSL_ENABLED" = "true" ]; then
    HTTP_PORT="80"
    HTTPS_PORT="443"
    prompt_ports
    if [ -z "$DOMAIN" ]; then
      read -rp "DOMAIN (contoh: api.absenta.id): " DOMAIN
      DOMAIN="$(printf '%s' "$DOMAIN" | tr -d '\r' | xargs)"
    fi
    if [ -z "${MAIN_DOMAIN:-}" ]; then
      d="${DOMAIN%%:*}"
      guess="${d#*.}"
      if [ "$guess" = "$d" ]; then
        guess="$d"
      fi
      read -rp "MAIN_DOMAIN (base domain, untuk CORS/tenant) [${guess}]: " MAIN_DOMAIN
      MAIN_DOMAIN="${MAIN_DOMAIN:-$guess}"
      MAIN_DOMAIN="$(printf '%s' "$MAIN_DOMAIN" | tr -d '\r' | xargs)"
    fi
    if [ -z "$CERTBOT_EMAIL" ]; then
      read -rp "EMAIL untuk Let’s Encrypt (contoh: asep@gmail.com): " CERTBOT_EMAIL
      CERTBOT_EMAIL="$(printf '%s' "$CERTBOT_EMAIL" | tr -d '\r' | xargs)"
    fi
  fi
}

if [ -t 0 ] && [ -t 1 ]; then
  prompt_ssl_single
fi

render_nginx_http_conf() {
  local main="${MAIN_DOMAIN:-}"
  if [ -z "$main" ]; then
    local h="${DOMAIN:-}"
    h="${h%%:*}"
    main="${h#*.}"
    if [ "$main" = "$h" ]; then
      main="localhost"
    fi
  fi
  if [ -f "$DIR/nginx/default.http.template.conf" ]; then
    sed "s/__MAIN_DOMAIN__/${main}/g" "$DIR/nginx/default.http.template.conf" > "$DIR/nginx/default.conf"
  fi
}

render_nginx_http_conf

prompt_frontend_repo() {
  if [ "${DEPLOY_FRONTEND:-true}" != "true" ]; then
    return 0
  fi
  local default_repo="${FRONTEND_REPO:-https://github.com/sharemovie1993/absenta_frontend.git}"
  local default_branch="${FRONTEND_BRANCH:-master}"
  read -rp "FRONTEND_REPO [${default_repo}]: " fr
  if [ -n "${fr:-}" ]; then
    FRONTEND_REPO="$fr"
  else
    FRONTEND_REPO="$default_repo"
  fi
  FRONTEND_REPO="$(printf '%s' "$FRONTEND_REPO" | tr -d '\r' | xargs)"
  FRONTEND_REPO="${FRONTEND_REPO%/}"
  read -rp "FRONTEND_BRANCH [${default_branch}]: " fb
  if [ -n "${fb:-}" ]; then
    FRONTEND_BRANCH="$fb"
  else
    FRONTEND_BRANCH="$default_branch"
  fi
  if [ -z "${FRONTEND_PATH:-}" ]; then
    FRONTEND_PATH="$DIR/../absenta_frontend"
  fi
}

if [ -t 0 ] && [ -t 1 ]; then
  prompt_frontend_repo
fi

prompt_public_urls_single() {
  if [ "$MODE" != "single" ]; then
    return 0
  fi
  local default_scheme="http"
  if [ "$SSL_ENABLED" = "true" ]; then
    default_scheme="https"
  fi
  local host="${DOMAIN:-localhost}"
  local port_part=""
  if [ "$SSL_ENABLED" = "true" ]; then
    if [ -n "${HTTPS_PORT:-}" ] && [ "$HTTPS_PORT" != "443" ]; then
      port_part=":${HTTPS_PORT}"
    fi
  else
    if [ -n "${HTTP_PORT:-}" ] && [ "$HTTP_PORT" != "80" ]; then
      port_part=":${HTTP_PORT}"
    fi
  fi
  local base_default="${default_scheme}://${host}${port_part}"
  if [ -z "${PUBLIC_APP_URL:-}" ]; then
    read -rp "PUBLIC_APP_URL [${base_default}]: " PUBLIC_APP_URL
    PUBLIC_APP_URL="${PUBLIC_APP_URL:-$base_default}"
  fi
  if [ -z "${PUBLIC_INVOICE_BASE_URL:-}" ]; then
    read -rp "PUBLIC_INVOICE_BASE_URL [${base_default}]: " PUBLIC_INVOICE_BASE_URL
    PUBLIC_INVOICE_BASE_URL="${PUBLIC_INVOICE_BASE_URL:-$base_default}"
  fi
  export PUBLIC_APP_URL PUBLIC_INVOICE_BASE_URL
}

prompt_public_urls_multi() {
  if [ "$MODE" != "multi" ]; then
    return 0
  fi
  if [ -z "${PUBLIC_APP_URL:-}" ]; then
    local default_scheme="http"
    if [ "$SSL_ENABLED" = "true" ]; then
      default_scheme="https"
    fi
    local host="${DOMAIN:-}"
    local port_part=""
    if [ -n "${host:-}" ]; then
      if [ "$SSL_ENABLED" = "true" ]; then
        if [ -n "${HTTPS_PORT:-}" ] && [ "$HTTPS_PORT" != "443" ]; then
          port_part=":${HTTPS_PORT}"
        fi
      else
        if [ -n "${HTTP_PORT:-}" ] && [ "$HTTP_PORT" != "80" ]; then
          port_part=":${HTTP_PORT}"
        fi
      fi
      local base_default="${default_scheme}://${host}${port_part}"
      read -rp "PUBLIC_APP_URL [${base_default}]: " PUBLIC_APP_URL
      PUBLIC_APP_URL="${PUBLIC_APP_URL:-$base_default}"
    else
      read -rp "PUBLIC_APP_URL (contoh: https://api.absenta.id): " PUBLIC_APP_URL
      PUBLIC_APP_URL="$(printf '%s' "$PUBLIC_APP_URL" | tr -d '\r' | xargs)"
    fi
  fi
  if [ -z "${PUBLIC_INVOICE_BASE_URL:-}" ]; then
    local base_default="${PUBLIC_APP_URL:-}"
    if [ -n "${base_default:-}" ]; then
      read -rp "PUBLIC_INVOICE_BASE_URL [${base_default}]: " PUBLIC_INVOICE_BASE_URL
      PUBLIC_INVOICE_BASE_URL="${PUBLIC_INVOICE_BASE_URL:-$base_default}"
    else
      read -rp "PUBLIC_INVOICE_BASE_URL (contoh: https://api.absenta.id): " PUBLIC_INVOICE_BASE_URL
      PUBLIC_INVOICE_BASE_URL="$(printf '%s' "$PUBLIC_INVOICE_BASE_URL" | tr -d '\r' | xargs)"
    fi
  fi
  export PUBLIC_APP_URL PUBLIC_INVOICE_BASE_URL
}

if [ -t 0 ] && [ -t 1 ]; then
  prompt_public_urls_single
  prompt_public_urls_multi
fi

save_single_state
save_multi_state

git_repo_url="$BACKEND_REPO"
git_auth_args=()
if [ -n "$GITHUB_TOKEN" ]; then
  build_git_auth_args "$GITHUB_TOKEN" "$GITHUB_USERNAME"
fi

git_ssh_cmd=""
if [[ "$git_repo_url" =~ ^git@github\.com: ]] || [[ "$git_repo_url" =~ ^ssh://git@github\.com/ ]]; then
  git_ssh_cmd="ssh -o StrictHostKeyChecking=accept-new"
fi

if [ ! -d "$BACKEND_PATH" ]; then
  mkdir -p "$(dirname "$BACKEND_PATH")"
  if [ -n "$git_ssh_cmd" ]; then
    GIT_SSH_COMMAND="$git_ssh_cmd" git clone --branch "$BACKEND_BRANCH" --depth 1 "$git_repo_url" "$BACKEND_PATH" || {
      echo "Gagal clone repo backend (SSH). Pastikan deploy key sudah terpasang di VPS (non-interaktif)."
      exit 1
    }
  else
    git "${git_auth_args[@]}" clone --branch "$BACKEND_BRANCH" --depth 1 "$git_repo_url" "$BACKEND_PATH" || {
      echo "Gagal clone repo backend (HTTPS)."
      echo ""
      echo "Cara paling mudah untuk repo PRIVATE:"
      echo "1) Buat GitHub Token (PAT) dengan akses repo (read)."
      echo "2) Jalankan deploy lalu masukkan token saat diminta (input disembunyikan)."
      echo ""
      exit 1
    }
  fi
else
  if [ -d "$BACKEND_PATH/.git" ]; then
    if [ -n "$git_ssh_cmd" ]; then
      GIT_SSH_COMMAND="$git_ssh_cmd" git -C "$BACKEND_PATH" fetch --prune origin "$BACKEND_BRANCH" || true
    else
      git "${git_auth_args[@]}" -C "$BACKEND_PATH" fetch --prune origin "$BACKEND_BRANCH" || true
    fi
    git -C "$BACKEND_PATH" checkout "$BACKEND_BRANCH" || true
    if [ -n "$git_ssh_cmd" ]; then
      GIT_SSH_COMMAND="$git_ssh_cmd" git -C "$BACKEND_PATH" pull --ff-only origin "$BACKEND_BRANCH" || true
    else
      git "${git_auth_args[@]}" -C "$BACKEND_PATH" pull --ff-only origin "$BACKEND_BRANCH" || true
    fi
  fi
fi

if [ "${DEPLOY_FRONTEND:-true}" = "true" ]; then
  if [ -z "${FRONTEND_PATH:-}" ]; then
    FRONTEND_PATH="$DIR/../absenta_frontend"
  fi
  FRONTEND_REPO="$(printf '%s' "$FRONTEND_REPO" | tr -d '\r' | xargs)"
  FRONTEND_REPO="${FRONTEND_REPO//\`/}"
  FRONTEND_REPO="${FRONTEND_REPO//\"/}"
  FRONTEND_REPO="${FRONTEND_REPO//\'/}"
  FRONTEND_REPO="${FRONTEND_REPO%/}"
  mkdir -p "$(dirname "$FRONTEND_PATH")"
  if [ ! -d "$FRONTEND_PATH" ]; then
    git "${git_auth_args[@]}" clone --branch "$FRONTEND_BRANCH" --depth 1 "$FRONTEND_REPO" "$FRONTEND_PATH" || {
      echo "Gagal clone repo frontend."
      exit 1
    }
  else
    if [ -d "$FRONTEND_PATH/.git" ]; then
      git "${git_auth_args[@]}" -C "$FRONTEND_PATH" fetch --prune origin "$FRONTEND_BRANCH" || true
      git -C "$FRONTEND_PATH" checkout "$FRONTEND_BRANCH" || true
      git "${git_auth_args[@]}" -C "$FRONTEND_PATH" pull --ff-only origin "$FRONTEND_BRANCH" || true
    fi
  fi
  export FRONTEND_PATH
fi

export BACKEND_PATH
$DOCKER_BIN compose -f "$COMPOSE_FILE" config >/dev/null

if [ "$STACK_DOWN_FIRST" = "true" ]; then
  $DOCKER_BIN compose -f "$COMPOSE_FILE" down || true
fi

build_args=()
if [ "$NO_CACHE" = "true" ]; then
  build_args+=(--no-cache)
fi
$DOCKER_BIN compose -f "$COMPOSE_FILE" build "${build_args[@]}"

if [ "${DEPLOY_FRONTEND:-true}" = "true" ]; then
  vite_api="${PUBLIC_APP_URL%/}/api"
  socket_scheme="ws"
  socket_port="${HTTP_PORT:-80}"
  if [ "$SSL_ENABLED" = "true" ]; then
    socket_scheme="wss"
    socket_port="${HTTPS_PORT:-443}"
  fi
  socket_host="${DOMAIN:-localhost}"
  socket_port_part=""
  if [ "$socket_scheme" = "wss" ]; then
    if [ -n "${socket_port:-}" ] && [ "$socket_port" != "443" ]; then
      socket_port_part=":${socket_port}"
    fi
  else
    if [ -n "${socket_port:-}" ] && [ "$socket_port" != "80" ]; then
      socket_port_part=":${socket_port}"
    fi
  fi
  vite_socket="${socket_scheme}://${socket_host}${socket_port_part}"
  $DOCKER_BIN build -t "$FRONTEND_IMAGE" -f "$DIR/frontend/Dockerfile" \
    --build-arg VITE_API_BASE_URL="$vite_api" \
    --build-arg VITE_SOCKET_URL="$vite_socket" \
    "$FRONTEND_PATH" "${build_args[@]}"
fi

env_dir="$DIR/../env"
tmp_env="/tmp/absenta-env.migrate.env"
umask 077
cat "$env_dir/env.common" "$env_dir/env.database" "$env_dir/env.redis" "$env_dir/env.production" > "$tmp_env" || true

if [ "$RUN_MIGRATE" = "true" ]; then
  if [ "$MODE" = "single" ]; then
    $DOCKER_BIN compose -f "$COMPOSE_FILE" up -d postgres redis
    max_pg_wait=180
    waited_pg=0
    until $DOCKER_BIN exec absenta-postgres pg_isready -U "${POSTGRES_USER:-postgres}" -d "${POSTGRES_DB:-absensi}" >/dev/null 2>&1; do
      waited_pg=$((waited_pg+5))
      if [ "$waited_pg" -ge "$max_pg_wait" ]; then
        echo "PostgreSQL belum siap"
        break
      fi
      sleep 5
    done
  fi
  $DOCKER_BIN build -t "$MIGRATE_IMAGE" --target build "$BACKEND_PATH" "${build_args[@]}"
  migrate_net_args=()
  if [ "$MODE" = "single" ]; then
    migrate_net_args+=(--network absenta-net)
  fi
  $DOCKER_BIN run --rm "${migrate_net_args[@]}" \
    --env-file "$tmp_env" \
    -e DATABASE_URL="$DATABASE_URL" \
    "$MIGRATE_IMAGE" \
    sh -lc "npx prisma migrate deploy"

  if [ "$RUN_SEED" = "true" ]; then
    echo "Menjalankan prisma db seed..."
    $DOCKER_BIN run --rm "${migrate_net_args[@]}" \
      --env-file "$tmp_env" \
      -e DATABASE_URL="$DATABASE_URL" \
      "$MIGRATE_IMAGE" \
      sh -lc "npx prisma db seed"
  fi
fi

$DOCKER_BIN compose -f "$COMPOSE_FILE" up -d --remove-orphans
$DOCKER_BIN ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

setup_ssl_cron_single() {
  if [ "$MODE" != "single" ] && [ "$MODE" != "multi" ]; then
    return 0
  fi
  if [ "$SSL_ENABLED" != "true" ]; then
    return 0
  fi
  if ! is_cmd sudo; then
    return 0
  fi
  if [ -z "${DOMAIN:-}" ] || [ -z "${CERTBOT_EMAIL:-}" ]; then
    return 0
  fi
  if [ ! -f "$DIR/nginx/default.https.template.conf" ]; then
    return 0
  fi

  cp "$DIR/nginx/default.conf" "$DIR/nginx/default.http.bak.conf" 2>/dev/null || true

  $DOCKER_BIN run --rm \
    -v absenta-letsencrypt:/etc/letsencrypt \
    -v absenta-certbot-www:/var/www/certbot \
    certbot/certbot \
    certonly --webroot -w /var/www/certbot \
    -d "$DOMAIN" \
    --email "$CERTBOT_EMAIL" \
    --agree-tos --non-interactive --no-eff-email || {
      echo "Gagal issue SSL. Pastikan DOMAIN sudah A record ke IP VPS dan port 80 terbuka."
      mv -f "$DIR/nginx/default.http.bak.conf" "$DIR/nginx/default.conf" 2>/dev/null || true
      $DOCKER_BIN exec absenta-nginx nginx -s reload >/dev/null 2>&1 || true
      return 1
    }

  main="${MAIN_DOMAIN:-}"
  if [ -z "$main" ]; then
    d="${DOMAIN%%:*}"
    main="${d#*.}"
    if [ "$main" = "$d" ]; then
      main="$d"
    fi
  fi
  sed -e "s/__DOMAIN__/${DOMAIN}/g" -e "s/__MAIN_DOMAIN__/${main}/g" "$DIR/nginx/default.https.template.conf" > "$DIR/nginx/default.conf"

  $DOCKER_BIN exec absenta-nginx nginx -t >/dev/null 2>&1 || {
    echo "Config nginx HTTPS tidak valid. Mengembalikan config HTTP."
    mv -f "$DIR/nginx/default.http.bak.conf" "$DIR/nginx/default.conf" 2>/dev/null || true
    $DOCKER_BIN exec absenta-nginx nginx -s reload >/dev/null 2>&1 || true
    return 1
  }

  $DOCKER_BIN exec absenta-nginx nginx -s reload >/dev/null 2>&1 || $DOCKER_BIN restart absenta-nginx >/dev/null 2>&1 || true

  sudo apt-get update -y >/dev/null 2>&1 || true
  sudo apt-get install -y cron >/dev/null 2>&1 || true

  docker_path="$(command -v docker || echo docker)"
  cat <<EOF | sudo tee /etc/cron.d/absenta-certbot >/dev/null
SHELL=/bin/sh
PATH=/usr/sbin:/usr/bin:/sbin:/bin
0 3 * * * root ${docker_path} run --rm -v absenta-letsencrypt:/etc/letsencrypt -v absenta-certbot-www:/var/www/certbot certbot/certbot renew --webroot -w /var/www/certbot --quiet && ${docker_path} exec absenta-nginx nginx -s reload >/dev/null 2>&1
EOF
  sudo chmod 644 /etc/cron.d/absenta-certbot >/dev/null 2>&1 || true
  sudo systemctl enable --now cron >/dev/null 2>&1 || true
}

if [ "$SSL_ENABLED" = "true" ]; then
  setup_ssl_cron_single || true
fi

ensure_standby() {
  local name="$1"
  local node_name="$2"
  local script="$3"
  if $DOCKER_BIN ps -a --format "{{.Names}}" | grep -q "^${name}\$" 2>/dev/null; then
    $DOCKER_BIN stop "$name" >/dev/null 2>&1 || true
    return 0
  fi
  local tmp="/tmp/absenta-worker-env-${node_name}.env"
  umask 077
  cat "$env_dir/env.common" "$env_dir/env.database" "$env_dir/env.redis" "$env_dir/env.production" > "$tmp" || true
  echo "NODE_NAME=${node_name}" >> "$tmp"
  $DOCKER_BIN create --name "$name" --restart unless-stopped --network absenta-net --env-file "$tmp" absenta-backend:latest node "$script" >/dev/null 2>&1 || true
}

ensure_standby "absenta-worker-attendance-2" "node-attendance" "dist/workers/attendance.worker.js"
ensure_standby "absenta-worker-attendance-3" "node-attendance" "dist/workers/attendance.worker.js"
ensure_standby "absenta-worker-attendance-4" "node-attendance" "dist/workers/attendance.worker.js"
ensure_standby "absenta-worker-billing-2" "node-billing" "dist/workers/billing.worker.js"
ensure_standby "absenta-worker-notification-2" "node-billing" "dist/workers/notification.worker.js"
exited="$($DOCKER_BIN ps -a --filter "status=exited" --format "{{.Names}}" || true)"
if [ -n "$exited" ]; then
  for n in $exited; do
    echo "==== LOG: $n ===="
    $DOCKER_BIN logs "$n" || true
    echo "=================="
  done
fi
if command -v curl >/dev/null 2>&1; then
  curl -s -o /dev/null -w "health http %{http_code}\n" http://localhost:3001/health || true
fi
exit 0
