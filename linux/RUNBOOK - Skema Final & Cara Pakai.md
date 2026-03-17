# RUNBOOK – Skema Final & Cara Pakai (Absenta Deploy + Toolbox + K3s/K8s)

Dokumen ini menjelaskan:
- skenario akhir yang ingin dicapai (topologi & alur trafik),
- langkah operasional “tanpa pusing” untuk owner,
- urutan eksekusi menu yang sudah tersedia (Toolbox + K8s menu),
- checklist verifikasi.

Target: Anda cukup menjalankan menu script, tanpa konfigurasi manual yang ribet.

---

## 1) Skema Akhir (Topologi)

### 1.1 Topologi Infrastruktur

```
Internet
   |
   v
[VPS REV PROXY] 1 vCPU / 1GB
  - Nginx/Traefik (SSL terminator)
  - WireGuard peer (wg0)
  - UFW firewall hardened
   |
   | (WireGuard tunnel)
   v
[VPS BACKEND] 8 vCPU / 8GB
  - API + Workers (Docker Compose atau k3s)
  - K3s (opsional, untuk simulasi Kubernetes single node)
  - WireGuard peer (wg0)
  - UFW firewall hardened
   |
   | (WireGuard tunnel)
   +--------------------------+
   |                          |
   v                          v
[VM POSTGRES – SEKOLAH]   [VM REDIS – SEKOLAH]
  - PostgreSQL only WG      - Redis only WG
  - listen wg-ip:5432       - bind wg-ip:6379
  - pg_hba allow WG subnet  - requirepass enabled
  - UFW allow WG subnet     - UFW allow WG subnet
```

### 1.2 Alur Trafik Aplikasi

```
User Internet
  -> VPS Reverse Proxy (publik HTTPS)
  -> (via WireGuard) VPS Backend (API/Ingress/NodePort)
  -> (via WireGuard) VM PostgreSQL dan VM Redis (sekolah)
```

Catatan:
- Reverse proxy tidak berbicara ke backend via IP publik, tapi via IP WireGuard.
- DB/Redis tidak exposed publik. Hanya bisa diakses dari subnet WireGuard.

---

## 2) Prinsip Operasional (Owner-Friendly)

Anda hanya perlu mengingat 3 menu:

1) **Toolbox** (dapur/bengkel infra): instal & konfigurasi server (WG, firewall, Postgres, Redis, SSH hardening, backup, monitoring)
2) **Deploy Absenta** (existing, Docker/compose) atau **K8s menu** (k3s single node)
3) **Monitoring menu** (health checks, node exporter, backup schedule)

Tujuan: Semua perubahan dilakukan via script menu, bukan edit manual.

---

## 3) Setup Pertama Kali (Checklist Urutan)

### 3.1 Setup VPS Reverse Proxy

Di VPS reverse proxy (publik):

1) Jalankan Toolbox

```bash
cd absenta-deploy/linux/toolbox
chmod +x absenta-toolbox.sh modules/*.sh lib/*.sh
./absenta-toolbox.sh
```

2) Pilih: **Role wizard → Reverse Proxy**
- Firewall baseline: allow SSH, 80/443, WireGuard UDP
- (opsional) hardening basic + chrony

3) Pilih: **WireGuard menu**
- Install WireGuard
- Init server / atau Add client sesuai desain jaringan WG yang Anda pakai
- Cek status

4) Konfigurasi reverse proxy upstream
- Upstream diarahkan ke IP WireGuard VPS backend.

---

### 3.2 Setup VPS Backend (API + Worker / k3s)

Di VPS backend:

1) Jalankan Toolbox → **Role wizard → Backend**
- Firewall baseline: allow SSH, WireGuard UDP
- (opsional) allow NodePort API dari IP WG reverse proxy

2) Pastikan WireGuard hidup (WireGuard menu → status)

3) Pilih mode menjalankan aplikasi:

#### Mode A – Docker Compose (yang Anda pakai sekarang)
- Jalankan deployment existing (menu 21 / single_no_nginx) seperti biasa.

#### Mode B – K3s/K8s Single Node (simulasi)

Jalankan menu K8s:

```bash
cd absenta-deploy/linux/k8s
chmod +x absenta-k8s.sh modules/*.sh lib/*.sh
./absenta-k8s.sh
```

Urutan:
- Install/Update k3s
- Deploy/Update Absenta (NodePort)
- Status & Logs untuk verifikasi

Reverse proxy upstream:
- `/api` -> `http://<WG_BACKEND_IP>:32001` (default NodePort API)
- Jika frontend dideploy ke k3s: `/` -> `http://<WG_BACKEND_IP>:32080`

---

### 3.3 Setup VM PostgreSQL (Sekolah)

Di VM PostgreSQL (sekolah):

1) Jalankan Toolbox → **Role wizard → PostgreSQL**
- Install PostgreSQL
- Set listen_addresses ke IP WG (mis. 10.8.0.10)
- Set pg_hba allow WG subnet (mis. 10.8.0.0/24) dengan scram-sha-256
- Firewall: allow WG subnet to 5432/tcp + allow SSH + allow wg udp

2) Buat database + user
- Toolbox → PostgreSQL menu → Create database + user

3) (Opsional) Jadwalkan backup
- Toolbox → Monitoring menu → Schedule PostgreSQL backup harian + rotasi

---

### 3.4 Setup VM Redis (Sekolah)

Di VM Redis (sekolah):

1) Jalankan Toolbox → **Role wizard → Redis**
- Install Redis
- Bind ke IP WG (mis. 10.8.0.11)
- Enable requirepass
- Firewall: allow WG subnet to 6379/tcp + allow SSH + allow wg udp

---

## 4) Checklist “Selesai & Aman”

### 4.1 Verifikasi Koneksi WireGuard
- Toolbox → Status server (lihat `wg show`)
- Monitoring menu → Health WG ping:
  - dari VPS backend ping VM postgres wg IP
  - dari VPS backend ping VM redis wg IP
  - dari VPS reverse proxy ping VPS backend wg IP

### 4.2 Verifikasi DB/Redis
- Monitoring menu → Health PostgreSQL connect test
- Monitoring menu → Health Redis ping test

### 4.3 Verifikasi Aplikasi
- Pastikan reverse proxy bisa akses API:
  - `https://domain-anda/api/health` (atau endpoint health yang tersedia)
- Jika k3s:
  - `kubectl get pods -n absenta`
  - `kubectl logs -n absenta deploy/backend-api`

---

## 5) Skenario Akhir yang Didapat

Jika seluruh langkah di atas selesai, Anda memperoleh:

- **Zero public exposure untuk DB/Redis** (hanya WireGuard)
- **Reverse proxy dan backend terhubung privat** (WireGuard)
- **Deploy modular**:
  - Toolbox untuk infra (wireguard, firewall, ssh, db, redis, monitoring, backup)
  - K8s menu untuk simulasi Kubernetes di single VPS backend
- **Jalur upgrade yang mulus**:
  - tetap bisa jalan di Docker compose (sekarang)
  - bisa simulasi k3s single node (tanpa ganti pola reverse proxy)
  - nanti mudah naik multi‑node/cluster

---

## 6) Catatan Penting (Keamanan & Risiko)

- **SSH hardening**: pastikan Anda sudah bisa login pakai SSH key sebelum mematikan password auth.
- **Netplan**: gunakan `netplan try` (sudah disediakan) agar rollback otomatis jika koneksi putus.
- **Backup**: backup harian penting karena DB on-prem dan tunnel bisa bermasalah sewaktu-waktu.

