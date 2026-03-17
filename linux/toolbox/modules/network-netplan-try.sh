#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

need_cmd netplan
need_cmd ip
need_cmd sed

echo "Netplan try = apply konfigurasi jaringan dengan auto rollback jika Anda tidak konfirmasi."
echo "Ini lebih aman daripada netplan apply."
echo ""

ip -br link || true
echo ""
read -rp "Interface (contoh eth0): " IFACE
[ -n "${IFACE:-}" ] || { echo "Interface kosong"; exit 1; }

read -rp "Static IP CIDR (contoh 192.168.1.10/24): " IP_CIDR
read -rp "Gateway (contoh 192.168.1.1): " GW
read -rp "DNS (pisahkan koma, contoh 1.1.1.1,8.8.8.8): " DNS

[ -n "${IP_CIDR:-}" ] || { echo "IP kosong"; exit 1; }
[ -n "${GW:-}" ] || { echo "Gateway kosong"; exit 1; }
[ -n "${DNS:-}" ] || { echo "DNS kosong"; exit 1; }

dns_list="$(printf '%s' "$DNS" | sed -E 's/[[:space:]]+//g; s/,/, /g')"

target="/etc/netplan/99-absenta-static.yaml"
ts="$(date +%Y%m%d_%H%M%S)"
if [ -f "$target" ]; then
  as_root cp -a "$target" "${target}.bak_${ts}"
fi

as_root bash -lc "cat > '$target' <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    ${IFACE}:
      dhcp4: no
      addresses: [${IP_CIDR}]
      routes:
        - to: default
          via: ${GW}
      nameservers:
        addresses: [${dns_list}]
EOF"

echo ""
echo "File dibuat: $target"
echo "Sekarang menjalankan: netplan try"
echo "Jika koneksi putus, tunggu timeout agar rollback otomatis."
echo ""

as_root netplan try

echo "Selesai"

