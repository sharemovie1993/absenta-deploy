#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

need_cmd curl
need_cmd uname

load_env_files

if [ "$(uname -s | tr '[:upper:]' '[:lower:]')" != "linux" ]; then
  echo "k3s install only supported on Linux"
  exit 1
fi

K3S_CHANNEL="${K3S_CHANNEL:-stable}"
K3S_DISABLE_TRAEFIK="${K3S_DISABLE_TRAEFIK:-false}"

INSTALL_ARGS=()
INSTALL_ARGS+=("INSTALL_K3S_CHANNEL=$K3S_CHANNEL")

# Detect WireGuard IP (e.g., 10.60.0.1)
WG_INTERFACE="${WG_INTERFACE:-wg0}"
WG_IP=$(ip -4 addr show "$WG_INTERFACE" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' || echo "")

if [ -n "$WG_IP" ]; then
  echo "Detected WireGuard IP: $WG_IP on $WG_INTERFACE"
  # Use WireGuard IP as node-ip and bind-address to ensure accessibility
  K3S_EXEC="--node-ip $WG_IP --bind-address $WG_IP"
else
  echo "WireGuard interface $WG_INTERFACE not found, using default interface"
  K3S_EXEC=""
fi

if [ "${K3S_DISABLE_TRAEFIK,,}" = "true" ]; then
  K3S_EXEC="${K3S_EXEC} --disable traefik"
fi

if [ -n "$K3S_EXEC" ]; then
  INSTALL_ARGS+=("INSTALL_K3S_EXEC=$(echo "$K3S_EXEC" | xargs)")
fi

echo "Installing k3s channel=$K3S_CHANNEL"
as_root env "${INSTALL_ARGS[@]}" sh -lc "curl -sfL https://get.k3s.io | sh -"

as_root sh -lc "mkdir -p /etc/absenta || true"
save_state_kv "ABSENTA_K8S_NAMESPACE" "$(ns_name)"

echo "k3s installed"
echo "kubectl: $(kubectl_bin)"

