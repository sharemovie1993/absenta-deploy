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

# Interactive IP Selection if possible
K3S_EXEC=""
if [ -t 0 ]; then
  echo "=== Pilih IP untuk K3s Networking ==="
  echo "Daftar Interface dan IP yang tersedia:"
  ip -4 -o addr show | awk '{print $2 " -> " $4}' | cut -d'/' -f1
  echo "-----------------------------------------------"
  
  WG_DEFAULT=$(ip -4 addr show wg0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1 || echo "")
  
  if [ -n "$WG_DEFAULT" ]; then
    read -rp "IP untuk NodePort (Default wg0: $WG_DEFAULT): " WG_IP
    WG_IP="${WG_IP:-$WG_DEFAULT}"
  else
    read -rp "IP untuk NodePort: " WG_IP
  fi
  
  if [ -n "$WG_IP" ]; then
    echo "Using IP: $WG_IP"
    K3S_EXEC="--node-ip $WG_IP --bind-address $WG_IP"
  fi
else
  # Non-interactive fallback (keep old logic but make it optional)
  WG_IP=$(ip -4 addr show wg0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1 || echo "")
  if [ -n "$WG_IP" ]; then
    K3S_EXEC="--node-ip $WG_IP --bind-address $WG_IP"
  fi
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

