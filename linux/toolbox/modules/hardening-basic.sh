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

as_root ufw default deny incoming
as_root ufw default allow outgoing
as_root ufw allow "${SSH_PORT:-22}/tcp"
as_root ufw --force enable

as_root systemctl enable --now fail2ban || true
as_root systemctl enable --now unattended-upgrades || true

echo "OK"

