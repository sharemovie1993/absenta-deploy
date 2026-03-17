# Absenta K8s (k3s) – Deploy Menu

Paket ini menambahkan menu deploy Kubernetes (k3s) tanpa mengubah `deploylinux.sh`.

## Jalankan Menu

```bash
cd absenta-deploy/linux/k8s
chmod +x absenta-k8s.sh modules/*.sh lib/*.sh
./absenta-k8s.sh
```

## Konsep (singkat)

- Reverse proxy publik tetap di VPS reverse proxy.
- Reverse proxy meneruskan trafik ke VPS backend via WireGuard.
- VPS backend menjalankan k3s single-node dan menjalankan API+workers sebagai pods.
- PostgreSQL dan Redis bisa berada di VM sekolah via WireGuard (URL diarahkan ke IP WireGuard).

## Konfigurasi ENV

Script memuat env dari:
- `/etc/absenta/k8s.env` (state)
- `../env/env.common`
- `../env/env.production`
- `../env/env.database` (butuh `DATABASE_URL=...`)
- `../env/env.redis` (butuh `REDIS_URL=...`)

Parameter penting:
- `ABSENTA_K8S_NAMESPACE` (default: `absenta`)
- `ABSENTA_BACKEND_IMAGE` (default: `absenta-backend:latest`)
- `ABSENTA_FRONTEND_IMAGE` (default: `absenta-frontend:latest`)
- `K8S_BACKEND_NODEPORT` (default: `32001`)
- `K8S_DEPLOY_FRONTEND` (default: `false`)

Replicas (default simulasi awal):
- `K8S_REPL_API=1`
- `K8S_REPL_ATTENDANCE=2`
- `K8S_REPL_NOTIFICATION=2`
- `K8S_REPL_BILLING=1`
- `K8S_REPL_ANALYTICS=1`
- `K8S_REPL_MAINTENANCE=1`
- `K8S_REPL_INFRA=1`

## Reverse Proxy (WireGuard)

Mode NodePort (paling mudah):
- upstream `/api` → `http://<WG_BACKEND_IP>:32001`
- jika frontend juga dideploy ke k3s, set `K8S_DEPLOY_FRONTEND=true` dan arahkan `/` ke `http://<WG_BACKEND_IP>:32080`

