#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../lib/common.sh"

echo ""
echo "=== Status Server ==="
echo "Host: $(hostname)"
echo "User: $(id -un) (uid=$(id -u))"
echo "Uptime:"
uptime || true
echo ""
echo "CPU:"
if is_cmd lscpu; then lscpu | sed -n '1,15p' || true; else echo "lscpu not found"; fi
echo ""
echo "RAM:"
if is_cmd free; then free -h || true; else echo "free not found"; fi
echo ""
echo "Disk:"
df -hT | head -n 40 || true
echo ""
echo "IP & Route:"
if is_cmd ip; then ip -br a || true; ip route | head -n 30 || true; else echo "ip not found"; fi
echo ""
echo "Listening Ports (top):"
if is_cmd ss; then ss -ltnp | head -n 30 || true; else echo "ss not found"; fi
echo ""
echo "Docker:"
if is_cmd docker; then docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" || true; else echo "docker not found"; fi
echo ""
echo "WireGuard:"
if is_cmd wg; then wg show || true; else echo "wg not found"; fi

