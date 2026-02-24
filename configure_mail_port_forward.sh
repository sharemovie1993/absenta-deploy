#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Script ini harus dijalankan sebagai root."
  exit 1
fi

echo "=== Wizard Konfigurasi Port Forward Mail Server (SMTP/IMAP) ==="
echo ""
echo "Script ini akan:"
echo "- Mengecek ketersediaan iptables dan ip command"
echo "- Menampilkan ringkasan aturan NAT terkait port mail saat ini"
echo "- Menambahkan DNAT dari IP publik VPS ke IP mail server di tunnel"
echo "- Menambahkan aturan FORWARD dan MASQUERADE jika diperlukan"
echo ""

if ! command -v iptables >/dev/null 2>&1; then
  echo "iptables tidak ditemukan di server ini. Install paket iptables terlebih dahulu."
  exit 1
fi

if ! command -v ip >/dev/null 2>&1; then
  echo "Perintah 'ip' tidak ditemukan. Script ini membutuhkan iproute2."
  exit 1
fi

DEFAULT_MAIL_IP="10.50.0.4"
read -p "IP internal mail server (default ${DEFAULT_MAIL_IP}): " MAIL_IP
MAIL_IP=${MAIL_IP:-$DEFAULT_MAIL_IP}

if [ -z "$MAIL_IP" ]; then
  echo "IP mail server tidak boleh kosong."
  exit 1
fi

DEFAULT_WG_IF="wg0"
read -p "Nama interface WireGuard untuk tunnel (default ${DEFAULT_WG_IF}): " WG_IFACE
WG_IFACE=${WG_IFACE:-$DEFAULT_WG_IF}

PUBLIC_IF=$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')
if [ -z "$PUBLIC_IF" ]; then
  PUBLIC_IF=$(ip route show default 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')
fi

echo "Interface publik terdeteksi: ${PUBLIC_IF:-tidak terdeteksi}"
read -p "Nama interface publik keluar internet (default ${PUBLIC_IF:-eth0}): " IFACE_OUT
IFACE_OUT=${IFACE_OUT:-${PUBLIC_IF:-eth0}}

echo ""
echo "=== Ringkasan aturan NAT terkait port mail SEBELUM perubahan ==="
iptables -t nat -S PREROUTING 2>/dev/null | grep -E 'dport (25|465|587|993|995)' || echo "(Tidak ada aturan PREROUTING khusus port mail yang terdeteksi)"
echo ""
echo "Aturan FORWARD terkait IP ${MAIL_IP}:"
iptables -S FORWARD 2>/dev/null | grep -F "$MAIL_IP" || echo "(Tidak ada aturan FORWARD spesifik untuk ${MAIL_IP} yang terdeteksi)"
echo ""

MAIL_PORTS="25 465 587 993 995"

for PORT in $MAIL_PORTS; do
  echo "Memastikan DNAT untuk port TCP ${PORT} -> ${MAIL_IP}:${PORT} ..."
  if iptables -t nat -C PREROUTING -i "$IFACE_OUT" -p tcp --dport "$PORT" -j DNAT --to-destination "${MAIL_IP}:${PORT}" 2>/dev/null; then
    echo "  - Aturan DNAT sudah ada, lewati."
  else
    iptables -t nat -A PREROUTING -i "$IFACE_OUT" -p tcp --dport "$PORT" -j DNAT --to-destination "${MAIL_IP}:${PORT}"
    echo "  - Aturan DNAT ditambahkan."
  fi

  echo "Memastikan aturan FORWARD untuk trafik ke ${MAIL_IP}:${PORT} ..."
  if iptables -C FORWARD -i "$IFACE_OUT" -o "$WG_IFACE" -p tcp -d "$MAIL_IP" --dport "$PORT" -j ACCEPT 2>/dev/null; then
    echo "  - Aturan FORWARD (IN -> WG) sudah ada."
  else
    iptables -A FORWARD -i "$IFACE_OUT" -o "$WG_IFACE" -p tcp -d "$MAIL_IP" --dport "$PORT" -j ACCEPT
    echo "  - Aturan FORWARD (IN -> WG) ditambahkan."
  fi

  if iptables -C FORWARD -i "$WG_IFACE" -o "$IFACE_OUT" -p tcp -s "$MAIL_IP" --sport "$PORT" -j ACCEPT 2>/dev/null; then
    echo "  - Aturan FORWARD (WG -> OUT) sudah ada."
  else
    iptables -A FORWARD -i "$WG_IFACE" -o "$IFACE_OUT" -p tcp -s "$MAIL_IP" --sport "$PORT" -j ACCEPT
    echo "  - Aturan FORWARD (WG -> OUT) ditambahkan."
  fi
done

echo ""
echo "Memastikan aturan MASQUERADE untuk trafik keluar dari ${MAIL_IP} melalui ${IFACE_OUT} ..."
if iptables -t nat -C POSTROUTING -s "$MAIL_IP" -o "$IFACE_OUT" -j MASQUERADE 2>/dev/null; then
  echo "  - Aturan MASQUERADE sudah ada."
else
  iptables -t nat -A POSTROUTING -s "$MAIL_IP" -o "$IFACE_OUT" -j MASQUERADE
  echo "  - Aturan MASQUERADE ditambahkan."
fi

echo ""
echo "=== Ringkasan aturan NAT terkait port mail SETELAH perubahan ==="
iptables -t nat -S PREROUTING 2>/dev/null | grep -E 'dport (25|465|587|993|995)' || echo "(Tidak ada aturan PREROUTING khusus port mail yang terdeteksi)"
echo ""
echo "Aturan FORWARD terkait IP ${MAIL_IP}:"
iptables -S FORWARD 2>/dev/null | grep -F "$MAIL_IP" || echo "(Tidak ada aturan FORWARD spesifik untuk ${MAIL_IP} yang terdeteksi)"
echo ""

if command -v netfilter-persistent >/dev/null 2>&1; then
  echo "Menyimpan konfigurasi iptables via netfilter-persistent..."
  netfilter-persistent save || echo "Gagal menyimpan iptables via netfilter-persistent."
else
  echo "netfilter-persistent tidak ditemukan. Aturan iptables ini akan hilang setelah reboot."
  echo "Pertimbangkan untuk menginstall paket iptables-persistent/netfilter-persistent agar aturan bertahan setelah reboot."
fi

echo ""
echo "Wizard konfigurasi port forward mail server selesai."

