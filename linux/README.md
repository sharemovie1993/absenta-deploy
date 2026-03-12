# Deploy Absenta (Linux / VPS)

## Prasyarat
- Ubuntu 22.04+ (direkomendasikan)
- Akses sudo
- Port terbuka: 3001 (API) dan 6379 (Redis) jika memakai Redis internal compose
- Database PostgreSQL sudah tersedia dan kredensialnya siap

## Struktur
- `linux/docker-compose.linux.yml` (Redis internal + API + workers)
- `linux/docker-compose.linux.external-redis.yml` (tanpa Redis service)
- `linux/deploy-multinode.sh` (script deploy idempotent)

## Konfigurasi ENV
Edit berkas di `../env/`:
- `env.common`
- `env.database` (wajib: `DATABASE_URL=...`)
- `env.redis` (wajib: `REDIS_URL=...`)
- `env.production`
- Opsional: `env.payment`, `env.email` (dipakai oleh backend-api)

## Deploy (Redis internal)
Jalankan dari server VPS:

```bash
cd absenta-deploy/linux
chmod +x deploy-multinode.sh
./deploy-multinode.sh
```

## Tanpa input username GitHub (non-interaktif)
Script `deploy-multinode.sh` diset non-interaktif (`GIT_TERMINAL_PROMPT=0`), jadi tidak akan meminta username/password.

Jika repo backend private, pilih salah satu:

- **Paling mudah (disarankan): jalankan deploy, lalu masukkan token saat diminta (input disembunyikan)**:

```bash
./deploy-multinode.sh
```

- **Pakai PAT (paling mudah)**:

```bash
export GITHUB_TOKEN="ghp_xxx"
./deploy-multinode.sh
```

Jika token fine-grained Anda tetap ditolak, coba set username GitHub juga:

```bash
export GITHUB_USERNAME="USERNAME_GITHUB_ANDA"
./deploy-multinode.sh
```

- **Paling mudah (tanpa export, simpan sekali di VPS)**:

```bash
sudo mkdir -p /etc/absenta
sudo sh -lc 'echo "ghp_xxx" > /etc/absenta/github.token'
sudo chmod 600 /etc/absenta/github.token
./deploy-multinode.sh
```

- **Pakai SSH deploy key (lebih aman untuk server)**:
  - Set `BACKEND_REPO` ke SSH:

```bash
BACKEND_REPO="git@github.com:sharemovie1993/absenta_backend.git" ./deploy-multinode.sh
```

  - Pastikan key sudah ada di VPS (misal `/root/.ssh/id_ed25519`) dan public key ditambahkan sebagai Deploy Key di repo.

## Deploy (Redis eksternal)

```bash
cd absenta-deploy/linux
COMPOSE_FILE="$PWD/docker-compose.linux.external-redis.yml" ./deploy-multinode.sh
```

## Menu deploy (1 klik)
Saat menjalankan `deploy-multinode.sh`, Anda akan diminta memilih:
- **Single instance**: nginx + postgresql + redis + api + workers di 1 mesin
- **Multi instance**: postgresql external + redis external, api + workers di mesin ini

Catatan port 80/443:
- Jika port 80/443 sudah dipakai aplikasi lain (misal CBT), pilih port alternatif (8080/8443) untuk testing.
- Untuk SSL Let’s Encrypt, port 80/443 harus bisa dipakai oleh nginx Absenta (sementara atau permanen).


File compose yang dipakai:
- Single: `docker-compose.linux.single.yml`
- Multi: `docker-compose.linux.multi.yml`

## Frontend (container)
- Frontend ikut di-deploy sebagai container dan di-proxy oleh nginx.
- Routing nginx:
  - `/api/*` dan `/socket.io/*` ke backend
  - selain itu ke frontend (SPA)
 
Catatan CORS (untuk domain sendiri):
- Jika frontend di `www.domain.com` dan API di `api.domain.com`, set `MAIN_DOMAIN=domain.com` saat deploy.

## Uninstall (hapus total)
Menu deploy menyediakan opsi uninstall untuk menghapus jejak:
- Stop & remove container
- Remove volume data (PostgreSQL/Redis/Let’s Encrypt)
- Remove image Absenta
- Remove config tersimpan di `/etc/absenta/*` dan cron renew SSL

## Domain + SSL (Single instance)
- Saat mode **single**, script akan menawarkan setup domain + HTTPS.
- Jika Anda pilih aktif, script akan:
  - issue sertifikat Let’s Encrypt via HTTP challenge (port 80)
  - switch nginx config ke HTTPS (port 443)
  - buat cron renew otomatis + reload nginx
- Domain, email Let’s Encrypt, dan URL publik (`PUBLIC_APP_URL` / `PUBLIC_INVOICE_BASE_URL`) diminta lewat prompt (tanpa edit `.env`).

Syarat:
- Domain (A record) sudah mengarah ke IP VPS
- Port 80 dan 443 terbuka di firewall/VPS panel

## Override lokasi source backend
Default script akan:
- pakai path legacy jika ada: `../../ProjekAbsenta/backend/absenta_backend`
- jika tidak ada: clone ke `../absenta_backend`

Untuk menentukan lokasi sendiri:

```bash
BACKEND_PATH=/opt/absenta/absenta_backend ./deploy-multinode.sh
```

## Migrate DB (Prisma)
Default `deploy-multinode.sh` menjalankan migrate otomatis via container Node:
- `npx prisma migrate deploy` (dijalankan dari image `absenta-backend-migrate:latest`, tanpa install npm ulang)

Untuk mematikan migrate:

```bash
RUN_MIGRATE=false ./deploy-multinode.sh
```

## Health check
Script akan cek:
- `http://localhost:3001/health`

Jika memakai reverse proxy, pastikan upstream mengarah ke port `3001`.

## Load test (real attendance)
Disarankan menjalankan k6 dari mesin terpisah (bukan VPS yang sama) untuk menghindari limit socket/ephemeral port.

Output summary k6 diarahkan ke:
- `ProjekAbsenta/backend/absenta_backend/logs/loadtest/*.json`
