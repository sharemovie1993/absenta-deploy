#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

need_cmd systemctl

echo "Hardening basic (konservatif)"
echo "- install: unattended-upgrades, fail2ban, ufw"
echo "- enable ufw safe defaults (deny incoming, allow outgoing, allow SSH)"
echo "- enable unattended upgrades"
echo "- enable fail2ban"

apt_ensure unattended-upgrades
apt_ensure fail2ban
ensure_ufw

as_root ufw default deny incoming >/dev/null
as_root ufw default allow outgoing >/dev/null
as_root ufw allow "${SSH_PORT:-22}/tcp" >/dev/null
as_root ufw --force enable >/dev/null

as_root systemctl enable --now fail2ban >/dev/null 2>&1 || true
as_root systemctl enable --now unattended-upgrades >/dev/null 2>&1 || true

echo "OK"

