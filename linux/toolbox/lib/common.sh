#!/usr/bin/env bash
set -euo pipefail

is_cmd() { command -v "$1" >/dev/null 2>&1; }
need_cmd() { is_cmd "$1" || { echo "Missing command: $1"; exit 1; }; }

SUDO_BIN="sudo"
if ! is_cmd sudo; then
  SUDO_BIN=""
fi

as_root() {
  if [ "$(id -u)" -eq 0 ] || [ -z "${SUDO_BIN}" ]; then
    "$@"
  else
    $SUDO_BIN "$@"
  fi
}

ubuntu_codename() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release || true
    printf '%s' "${UBUNTU_CODENAME:-}"
    return
  fi
  printf ''
}

apt_update_once() {
  if [ -z "${_APT_UPDATED_ONCE:-}" ]; then
    as_root apt-get update -y
    _APT_UPDATED_ONCE="yes"
  fi
}

apt_ensure() {
  local pkg="$1"
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    apt_update_once
    as_root apt-get install -y "$pkg"
  fi
}

ensure_systemd() {
  is_cmd systemctl || { echo "systemctl not found (systemd required)"; exit 1; }
}

download_file() {
  local url="$1"
  local out="$2"
  need_cmd curl
  curl -fsSL "$url" -o "$out"
}

ensure_ufw() { apt_ensure ufw; }
ensure_wireguard_tools() { apt_ensure wireguard; apt_ensure wireguard-tools; }
ensure_postgres() { apt_ensure postgresql; apt_ensure postgresql-contrib; }
ensure_redis() { apt_ensure redis-server; }

wg_iface() { printf '%s' "${WG_IFACE:-wg0}"; }
wg_dir() { printf '%s' "${WG_DIR:-/etc/wireguard}"; }
wg_port() { printf '%s' "${WG_PORT:-51820}"; }
