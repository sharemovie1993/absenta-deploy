#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

echo "Memastikan paket openssh-server terpasang..."
apt update -y
apt install -y openssh-server

SSHD_CONF="/etc/ssh/sshd_config"

if [ -f "$SSHD_CONF" ]; then
  cp "$SSHD_CONF" "${SSHD_CONF}.bak.$(date +%Y%m%d%H%M%S)"
fi

read -p "Port SSH yang akan digunakan (default 22): " SSH_PORT
SSH_PORT=${SSH_PORT:-22}

if grep -q "^#Port " "$SSHD_CONF" || grep -q "^Port " "$SSHD_CONF"; then
  sed -i "s/^#Port .*/Port ${SSH_PORT}/" "$SSHD_CONF" || true
  sed -i "s/^Port .*/Port ${SSH_PORT}/" "$SSHD_CONF" || true
else
  echo "Port ${SSH_PORT}" >> "$SSHD_CONF"
fi

if grep -q "^PermitRootLogin" "$SSHD_CONF"; then
  sed -i "s/^PermitRootLogin.*/PermitRootLogin prohibit-password/" "$SSHD_CONF"
else
  echo "PermitRootLogin prohibit-password" >> "$SSHD_CONF"
fi

read -p "Nonaktifkan login password SSH dan izinkan hanya key auth? (y/n, default n): " HARDEN_SSH
HARDEN_SSH=${HARDEN_SSH:-n}

if [ "$HARDEN_SSH" = "y" ] || [ "$HARDEN_SSH" = "Y" ]; then
  if grep -q "^PasswordAuthentication" "$SSHD_CONF"; then
    sed -i "s/^PasswordAuthentication.*/PasswordAuthentication no/" "$SSHD_CONF"
  else
    echo "PasswordAuthentication no" >> "$SSHD_CONF"
  fi
fi

read -p "Konfigurasi UFW untuk mengizinkan port SSH ${SSH_PORT}? (y/n, default y): " CONFIG_UFW
CONFIG_UFW=${CONFIG_UFW:-y}

if [ "$CONFIG_UFW" = "y" ] || [ "$CONFIG_UFW" = "Y" ]; then
  if ! command -v ufw >/dev/null 2>&1; then
    apt install -y ufw
  fi
  ufw allow "${SSH_PORT}"/tcp || true
fi

systemctl enable ssh || systemctl enable sshd || true
systemctl restart ssh || systemctl restart sshd

echo "Deploy SSH server dan hardening dasar selesai."
echo "Pastikan kunci SSH sudah dikonfigurasi sebelum menonaktifkan login password."

