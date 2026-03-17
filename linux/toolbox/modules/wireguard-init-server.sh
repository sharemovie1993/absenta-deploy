#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

need_cmd wg
need_cmd wg-quick
need_cmd sysctl
need_cmd systemctl

IFACE="$(wg_iface)"
WG_DIR_PATH="$(wg_dir)"
PORT="$(wg_port)"

read -rp "Server WG address CIDR (contoh 10.8.0.1/24): " WG_ADDRESS
read -rp "Listen port [${PORT}]: " PORT_IN
PORT="${PORT_IN:-$PORT}"
read -rp "WAN interface for NAT (contoh eth0) [skip untuk tanpa NAT]: " WAN_IF

as_root mkdir -p "$WG_DIR_PATH"
as_root chmod 700 "$WG_DIR_PATH" >/dev/null 2>&1 || true

if [ ! -f "$WG_DIR_PATH/${IFACE}.key" ]; then
  as_root bash -lc "umask 077 && wg genkey | tee '$WG_DIR_PATH/${IFACE}.key' | wg pubkey > '$WG_DIR_PATH/${IFACE}.pub'"
fi

PRIV="$(as_root cat "$WG_DIR_PATH/${IFACE}.key")"

POST_UP=""
POST_DOWN=""
if [ -n "${WAN_IF:-}" ]; then
  POST_UP="iptables -A FORWARD -i ${IFACE} -j ACCEPT; iptables -A FORWARD -o ${IFACE} -j ACCEPT; iptables -t nat -A POSTROUTING -o ${WAN_IF} -j MASQUERADE"
  POST_DOWN="iptables -D FORWARD -i ${IFACE} -j ACCEPT; iptables -D FORWARD -o ${IFACE} -j ACCEPT; iptables -t nat -D POSTROUTING -o ${WAN_IF} -j MASQUERADE"
  as_root sysctl -w net.ipv4.ip_forward=1 >/dev/null
  as_root bash -lc "printf '\nnet.ipv4.ip_forward=1\n' >> /etc/sysctl.conf"
fi

cfg="$WG_DIR_PATH/${IFACE}.conf"
as_root bash -lc "cat > '$cfg' <<EOF
[Interface]
Address = ${WG_ADDRESS}
ListenPort = ${PORT}
PrivateKey = ${PRIV}
${POST_UP:+PostUp = ${POST_UP}}
${POST_DOWN:+PostDown = ${POST_DOWN}}
EOF"

as_root chmod 600 "$cfg" >/dev/null 2>&1 || true
as_root systemctl enable --now "wg-quick@${IFACE}" >/dev/null 2>&1 || true

echo "WireGuard server initialized: $cfg"
echo "Public key:"
as_root cat "$WG_DIR_PATH/${IFACE}.pub" || true

