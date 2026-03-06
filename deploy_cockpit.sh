#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

if command -v apt-get >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y cockpit
elif command -v apt >/dev/null 2>&1; then
  apt update -y
  apt install -y cockpit
else
  echo "Hanya mendukung distro berbasis Debian/Ubuntu (apt/apt-get)."
  exit 1
fi

systemctl enable --now cockpit.socket

if command -v ufw >/dev/null 2>&1; then
  ufw allow 9090/tcp || true
elif command -v firewall-cmd >/dev/null 2>&1; then
  firewall-cmd --permanent --add-service=cockpit || firewall-cmd --permanent --add-port=9090/tcp || true
  firewall-cmd --reload || true
elif command -v iptables >/dev/null 2>&1; then
  iptables -C INPUT -p tcp --dport 9090 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 9090 -j ACCEPT || true
  if command -v netfilter-persistent >/dev/null 2>&1; then
    netfilter-persistent save || true
  fi
fi

HOST_IP=""
if command -v hostname -I >/dev/null 2>&1; then
  HOST_IP=$(hostname -I | awk '{print $1}')
fi
if [ -z "$HOST_IP" ] && command -v ip >/dev/null 2>&1; then
  HOST_IP=$(ip -4 addr show | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)
fi
if [ -z "$HOST_IP" ]; then
  HOST_IP="IP-SERVER"
fi

echo "Cockpit aktif. Akses: https://${HOST_IP}:9090"
echo "Login menggunakan user sistem (root atau user sudo)."
