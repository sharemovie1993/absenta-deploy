#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

need_cmd wg
need_cmd wg-quick
need_cmd systemctl

IFACE="$(wg_iface)"
WG_DIR_PATH="$(wg_dir)"
PORT="$(wg_port)"

srv_cfg="$WG_DIR_PATH/${IFACE}.conf"
[ -f "$srv_cfg" ] || { echo "Server config not found: $srv_cfg (run init server first)"; exit 1; }
[ -f "$WG_DIR_PATH/${IFACE}.pub" ] || { echo "Server pubkey not found"; exit 1; }

read -rp "Client name (contoh sekolah-a): " NAME
NAME="$(canonicalize_node_id "$NAME")"
[ -n "$NAME" ] || { echo "Client name empty"; exit 1; }

read -rp "Client WG address CIDR (contoh 10.8.0.10/32): " CLIENT_ADDR
read -rp "Server endpoint host:port (contoh 1.2.3.4:${PORT}): " ENDPOINT
read -rp "AllowedIPs on client (default 10.8.0.0/24) [10.8.0.0/24]: " ALLOWED
ALLOWED="${ALLOWED:-10.8.0.0/24}"

client_key="$WG_DIR_PATH/${IFACE}_${NAME}.key"
client_pub="$WG_DIR_PATH/${IFACE}_${NAME}.pub"
client_cfg="$WG_DIR_PATH/${IFACE}_${NAME}.conf"

as_root bash -lc "umask 077 && wg genkey | tee '$client_key' | wg pubkey > '$client_pub'"
CPRIV="$(as_root cat "$client_key")"
CPUB="$(as_root cat "$client_pub")"
SPUB="$(as_root cat "$WG_DIR_PATH/${IFACE}.pub")"

as_root bash -lc "cat > '$client_cfg' <<EOF
[Interface]
PrivateKey = ${CPRIV}
Address = ${CLIENT_ADDR}
DNS = 1.1.1.1

[Peer]
PublicKey = ${SPUB}
Endpoint = ${ENDPOINT}
AllowedIPs = ${ALLOWED}
PersistentKeepalive = 25
EOF"

as_root chmod 600 "$client_cfg" >/dev/null 2>&1 || true

as_root bash -lc "grep -q \"# absenta-client:${NAME}\" '$srv_cfg' || cat >> '$srv_cfg' <<EOF

# absenta-client:${NAME}
[Peer]
PublicKey = ${CPUB}
AllowedIPs = ${CLIENT_ADDR}
EOF"

as_root systemctl restart "wg-quick@${IFACE}" >/dev/null 2>&1 || true

echo "Client config created: $client_cfg"
echo "Share this file to the client machine."

