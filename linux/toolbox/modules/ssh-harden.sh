#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

need_cmd systemctl
need_cmd sshd
need_cmd sed

cfg="/etc/ssh/sshd_config"
[ -f "$cfg" ] || { echo "Missing: $cfg"; exit 1; }

echo "Hardening SSH akan:"
echo "- PermitRootLogin no"
echo "- PasswordAuthentication no"
echo "- PubkeyAuthentication yes"
echo "- (opsional) ganti Port"
echo ""
echo "PENTING: pastikan user Anda sudah punya SSH key yang berfungsi sebelum disable password."
echo ""

read -rp "Ganti port SSH? (y/n) [n]: " ch
ch="${ch:-n}"
NEW_PORT=""
if [ "${ch,,}" = "y" ]; then
  read -rp "Port baru (contoh 2222): " NEW_PORT
fi

echo ""
echo "Ketik APPLY untuk lanjut (selain itu batal): "
read -r CONFIRM
if [ "${CONFIRM:-}" != "APPLY" ]; then
  echo "Batal"
  exit 0
fi

ts="$(date +%Y%m%d_%H%M%S)"
as_root cp -a "$cfg" "${cfg}.bak_${ts}"

set_kv() {
  local key="$1"
  local val="$2"
  if as_root grep -qE "^${key}\s" "$cfg"; then
    as_root sed -i -E "s/^${key}\s+.*/${key} ${val}/" "$cfg"
  else
    as_root bash -lc "printf '\n%s %s\n' '$key' '$val' >> '$cfg'"
  fi
}

set_kv "PermitRootLogin" "no"
set_kv "PasswordAuthentication" "no"
set_kv "PubkeyAuthentication" "yes"
if [ -n "${NEW_PORT:-}" ]; then
  set_kv "Port" "${NEW_PORT}"
fi

as_root sshd -t
as_root systemctl restart ssh || as_root systemctl restart sshd

echo "OK. Backup: ${cfg}.bak_${ts}"
echo "Cek status dengan menu SSH Status."

