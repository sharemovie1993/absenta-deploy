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
STACK_DOWN_FIRST="${STACK_DOWN_FIRST:-true}"
MIGRATE_IMAGE="${MIGRATE_IMAGE:-absenta-backend-migrate:latest}"
SINGLE_STATE_FILE="${SINGLE_STATE_FILE:-/etc/absenta/single.env}"
MULTI_STATE_FILE="${MULTI_STATE_FILE:-/etc/absenta/multi.env}"
SSL_ENABLED="${SSL_ENABLED:-}"
DOMAIN="${DOMAIN:-}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"
PUBLIC_APP_URL="${PUBLIC_APP_URL:-}"
PUBLIC_INVOICE_BASE_URL="${PUBLIC_INVOICE_BASE_URL:-}"

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
        sudo rm -f /etc/absenta/single.env /etc/absenta/multi.env || true
      else
        rm -f /etc/absenta/single.env /etc/absenta/multi.env || true
      fi
      echo "Config reset OK"
      exit 0
      ;;
  esac
}

if [ "$ACTION" != "deploy" ]; then
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
    echo "CERTBOT_EMAIL=${CERTBOT_EMAIL:-}"
    echo "SSL_ENABLED=${SSL_ENABLED:-}"
    echo "PUBLIC_APP_URL=${PUBLIC_APP_URL:-}"
    echo "PUBLIC_INVOICE_BASE_URL=${PUBLIC_INVOICE_BASE_URL:-}"
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
  } > "$tmp_state"
  sudo mv "$tmp_state" "$MULTI_STATE_FILE" >/dev/null 2>&1 || true
  sudo chmod 600 "$MULTI_STATE_FILE" >/dev/null 2>&1 || true
}

load_single_state
load_multi_state

if [ -z "$GITHUB_TOKEN" ]; then
  token_candidates=(
    "$DIR/../env/github.token"
    "$HOME/.config/absenta/github.token"
    "/etc/absenta/github.token"
  )
  for f in "${token_candidates[@]}"; do
    if [ -f "$f" ]; then
      GITHUB_TOKEN="$(tr -d '\r\n ' < "$f" || true)"
      break
    fi
  done
fi

if [ -z "$GITHUB_TOKEN" ]; then
  if [[ "$BACKEND_REPO" =~ ^https://github\.com/ ]]; then
    if [ -t 0 ] && [ -t 1 ]; then
      read -rsp "Masukkan GitHub Token (tidak akan tampil): " GITHUB_TOKEN
      echo ""
    fi
  fi
fi

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
  if [ "$MODE" != "single" ]; then
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
    if [ -z "$DOMAIN" ]; then
      read -rp "DOMAIN (contoh: api.absenta.id): " DOMAIN
      DOMAIN="$(printf '%s' "$DOMAIN" | tr -d '\r' | xargs)"
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

prompt_public_urls_single() {
  if [ "$MODE" != "single" ]; then
    return 0
  fi
  local default_scheme="http"
  if [ "$SSL_ENABLED" = "true" ]; then
    default_scheme="https"
  fi
  local base_default=""
  if [ -n "${DOMAIN:-}" ]; then
    base_default="${default_scheme}://${DOMAIN}"
  else
    base_default="${default_scheme}://localhost"
  fi
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
    read -rp "PUBLIC_APP_URL (contoh: https://api.absenta.id): " PUBLIC_APP_URL
    PUBLIC_APP_URL="$(printf '%s' "$PUBLIC_APP_URL" | tr -d '\r' | xargs)"
  fi
  if [ -z "${PUBLIC_INVOICE_BASE_URL:-}" ]; then
    read -rp "PUBLIC_INVOICE_BASE_URL (contoh: https://api.absenta.id): " PUBLIC_INVOICE_BASE_URL
    PUBLIC_INVOICE_BASE_URL="$(printf '%s' "$PUBLIC_INVOICE_BASE_URL" | tr -d '\r' | xargs)"
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
if [ -n "$GITHUB_TOKEN" ] && [[ "$BACKEND_REPO" =~ ^https://github\.com/ ]]; then
  if ! is_cmd base64; then
    echo "base64 belum tersedia. Instal dulu: sudo apt-get update && sudo apt-get install -y coreutils"
    exit 1
  fi
  basic="$(printf '%s:%s' "$GITHUB_USERNAME" "$GITHUB_TOKEN" | base64 | tr -d '\n')"
  git_auth_args+=(-c "http.https://github.com/.extraheader=AUTHORIZATION: basic ${basic}")
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
      echo "Alternatif: simpan token sekali di /etc/absenta/github.token"
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
  $DOCKER_BIN run --rm \
    --env-file "$tmp_env" \
    -e DATABASE_URL="$DATABASE_URL" \
    "$MIGRATE_IMAGE" \
    sh -lc "npx prisma migrate deploy"
fi

$DOCKER_BIN compose -f "$COMPOSE_FILE" up -d --remove-orphans
$DOCKER_BIN ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"

setup_ssl_cron_single() {
  if [ "$MODE" != "single" ] || [ "$SSL_ENABLED" != "true" ]; then
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

  sed "s/__DOMAIN__/${DOMAIN}/g" "$DIR/nginx/default.https.template.conf" > "$DIR/nginx/default.conf"

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

if [ "$MODE" = "single" ] && [ "$SSL_ENABLED" = "true" ]; then
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
