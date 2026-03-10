#!/bin/bash
set -e

if [ "$(id -u)" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root"
  exit 1
fi

echo "Update sistem dan instal paket keamanan dasar"
apt-get update -y
apt-get upgrade -y
apt-get install -y ufw fail2ban unattended-upgrades

echo "Konfigurasi unattended-upgrades"
dpkg-reconfigure -f noninteractive unattended-upgrades || true

read -p "Port SSH yang digunakan server ini (default 22): " SSH_PORT
if [ -z "$SSH_PORT" ]; then
  SSH_PORT=22
fi

read -p "Izinkan HTTP port 80? (y/n, default n): " ALLOW_HTTP
read -p "Izinkan HTTPS port 443? (y/n, default y): " ALLOW_HTTPS

ALLOW_HTTP=${ALLOW_HTTP:-n}
ALLOW_HTTPS=${ALLOW_HTTPS:-y}

echo "Konfigurasi firewall UFW"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}"/tcp

if [ "$ALLOW_HTTP" = "y" ] || [ "$ALLOW_HTTP" = "Y" ]; then
  ufw allow 80/tcp
fi

if [ "$ALLOW_HTTPS" = "y" ] || [ "$ALLOW_HTTPS" = "Y" ]; then
  ufw allow 443/tcp
fi

ufw --force enable

read -p "Nonaktifkan login password SSH dan mengizinkan hanya key auth? (y/n, default n): " HARDEN_SSH
HARDEN_SSH=${HARDEN_SSH:-n}

if [ "$HARDEN_SSH" = "y" ] || [ "$HARDEN_SSH" = "Y" ]; then
  SSHD_CONF="/etc/ssh/sshd_config"
  if [ -f "$SSHD_CONF" ]; then
    cp "$SSHD_CONF" "${SSHD_CONF}.bak.$(date +%Y%m%d%H%M%S)"
    if grep -q "^PasswordAuthentication" "$SSHD_CONF"; then
      sed -i "s/^PasswordAuthentication.*/PasswordAuthentication no/" "$SSHD_CONF"
    else
      echo "PasswordAuthentication no" >> "$SSHD_CONF"
    fi
    if grep -q "^PermitRootLogin" "$SSHD_CONF"; then
      sed -i "s/^PermitRootLogin.*/PermitRootLogin prohibit-password/" "$SSHD_CONF"
    else
      echo "PermitRootLogin prohibit-password" >> "$SSHD_CONF"
    fi
    systemctl restart sshd || systemctl restart ssh
  fi
fi

echo "Hardening dasar selesai"

