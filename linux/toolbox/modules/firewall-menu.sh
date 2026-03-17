#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

ensure_ufw

allow_ssh() {
  local port="${SSH_PORT:-22}"
  as_root ufw allow "${port}/tcp"
  echo "OK allow SSH ${port}/tcp"
}

allow_http_https() {
  as_root ufw allow 80/tcp
  as_root ufw allow 443/tcp
  echo "OK allow 80/tcp, 443/tcp"
}

allow_wireguard() {
  local port
  port="$(wg_port)"
  as_root ufw allow "${port}/udp"
  echo "OK allow WireGuard ${port}/udp"
}

allow_from_wg_to_port() {
  read -rp "WG subnet (contoh 10.8.0.0/24): " wgsub
  read -rp "Port (contoh 5432): " p
  read -rp "Proto (tcp/udp) [tcp]: " proto
  proto="${proto:-tcp}"
  as_root ufw allow from "$wgsub" to any port "$p" proto "$proto"
  echo "OK allow from ${wgsub} to port ${p}/${proto}"
}

enable_ufw_safe() {
  as_root ufw default deny incoming
  as_root ufw default allow outgoing
  allow_ssh
  as_root ufw --force enable
  echo "UFW enabled (default deny incoming, allow outgoing)"


while true; do
  echo ""
  echo "=== Firewall (UFW) Menu ==="
  echo "1) Status"
  echo "2) Enable safe defaults (deny incoming, allow outgoing, allow SSH)"
  echo "3) Allow HTTP/HTTPS (80/443)"
  echo "4) Allow WireGuard (UDP)"
  echo "5) Allow from WG subnet to port (contoh 5432/6379)"
  echo "6) List rules (numbered)"
  echo "7) Delete rule by number"
  echo "0) Back"
  read -rp "Pilih: " opt
  case "${opt:-}" in
    1) as_root ufw status verbose || true ;;
    2) enable_ufw_safe ;;
    3) allow_http_https ;;
    4) allow_wireguard ;;
    5) allow_from_wg_to_port ;;
    6) as_root ufw status numbered || true ;;
    7)
      as_root ufw status numbered || true
      read -rp "Nomor rule yang dihapus: " n
      as_root ufw --force delete "$n" || true
      ;;
    0) exit 0 ;;
    *) echo "Pilihan tidak dikenal" ;;
  esac
done

