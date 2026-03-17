#!/usr/bin/env bash
set -euo pipefail

echo "=== Network Status ==="
if command -v ip >/dev/null 2>&1; then
  ip -br a || true
  echo ""
  ip route | head -n 40 || true
else
  echo "ip not found"
fi

echo ""
echo "DNS (/etc/resolv.conf):"
cat /etc/resolv.conf 2>/dev/null || true

echo ""
echo "Netplan files:"
ls -la /etc/netplan 2>/dev/null || true
for f in /etc/netplan/*.yaml /etc/netplan/*.yml; do
  [ -f "$f" ] || continue
  echo ""
  echo "--- $f ---"
  sed -n '1,200p' "$f" || true
done

