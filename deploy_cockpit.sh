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

read -p "Buat akun user Linux untuk login Cockpit? (y/n, default y): " MAKE_USER
MAKE_USER=${MAKE_USER:-y}
if [ "$MAKE_USER" = "y" ] || [ "$MAKE_USER" = "Y" ]; then
  read -p "Username: " NEWUSER
  if [ -z "$NEWUSER" ]; then
    echo "Username wajib."
  else
    if id -u "$NEWUSER" >/dev/null 2>&1; then
      read -p "User sudah ada. Reset password? (y/n, default n): " RESET_PW
      RESET_PW=${RESET_PW:-n}
      if [ "$RESET_PW" = "y" ] || [ "$RESET_PW" = "Y" ]; then
        read -s -p "Password baru: " NEWPASS; echo ""
        if [ -n "$NEWPASS" ]; then
          echo "$NEWUSER:$NEWPASS" | chpasswd || true
        else
          echo "Password kosong, lewati reset."
        fi
      fi
    else
      if command -v adduser >/dev/null 2>&1; then
        adduser --gecos "" --disabled-password "$NEWUSER"
      elif command -v useradd >/dev/null 2>&1; then
        useradd -m -s /bin/bash "$NEWUSER"
      fi
      read -s -p "Password: " NEWPASS; echo ""
      if [ -n "$NEWPASS" ]; then
        echo "$NEWUSER:$NEWPASS" | chpasswd || true
      else
        echo "Password kosong, user dibuat tanpa password."
      fi
    fi
    read -p "Tambahkan user ke grup sudo/wheel? (y/n, default y): " ADD_SUDO
    ADD_SUDO=${ADD_SUDO:-y}
    if [ "$ADD_SUDO" = "y" ] || [ "$ADD_SUDO" = "Y" ]; then
      if getent group sudo >/dev/null 2>&1; then
        usermod -aG sudo "$NEWUSER" || true
      elif getent group wheel >/dev/null 2>&1; then
        usermod -aG wheel "$NEWUSER" || true
      fi
    fi
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
