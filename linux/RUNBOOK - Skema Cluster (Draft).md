# RUNBOOK – Skema Cluster (Draft)

Dokumen ini adalah gambaran skenario cluster (multi node) sebagai kelanjutan dari skema single node. Fokus: tetap owner-friendly, tetap via WireGuard, dan tetap bisa berkembang ke Kubernetes “beneran” ketika sudah siap.

Status: **draft** (topologi & langkah umum sudah ada; script otomatis untuk cluster bisa ditambahkan bertahap).

---

## 1) Tujuan Cluster

Saat tenant naik, kebutuhan biasanya bukan hanya “upgrade VPS”, tapi:
- API butuh replika lebih banyak (high availability),
- worker butuh replika lebih banyak (throughput),
- workload dipisahkan per node (supaya stabil),
- rolling update lebih aman.

---

## 2) Topologi Cluster (Rekomendasi)

```
Internet
  |
  v
[VPS REV PROXY] (publik)
  - SSL terminator
  - WireGuard peer
  |
  | (WireGuard tunnel)
  v
[K3S CLUSTER – VPS BACKEND]
  - Node 1: control-plane + worker (opsional)
  - Node 2..N: worker nodes
  - Ingress controller (Traefik/Nginx)
  - Absenta API deployment (replicas > 1)
  - Absenta workers deployment (replicas sesuai kebutuhan)

           (WireGuard tunnel)
                |
                v
      [VM POSTGRES] + [VM REDIS] (sekolah/on-prem) atau managed/external
```

Catatan:
- Untuk cluster, lebih baik DB/Redis berada di jaringan yang stabil dan latensi rendah. On-prem via WireGuard tetap bisa untuk simulasi, tetapi produksi besar umumnya dipindahkan ke managed/external.

---

## 3) Pola Routing

Opsi yang paling simple dan tetap aman:
- Reverse proxy (publik) -> WireGuard -> Ingress controller di cluster (port 80/443 internal via WG)
- Ingress controller -> service backend-api -> pods

Untuk tahap awal, NodePort juga bisa, tapi pada cluster multi-node, Ingress lebih rapi.

---

## 4) Perubahan dari Single Node

- Single node: semua pod berada di 1 VPS backend.
- Cluster: pod tersebar di beberapa node, **Service** dan **Ingress** yang mengatur routing.
- Scaling: tinggal naikkan replicas deployment (atau otomatis pakai HPA/KEDA).

---

## 5) Minimum Checklist untuk Cluster “Layak Operasi”

- Minimal 2 node (1 control-plane, 1 worker).
- Reverse proxy tetap via WireGuard ke jaringan cluster.
- Monitoring node exporter per node.
- Backup Postgres terjadwal.
- Firewall role-based di tiap node (SSH + WG + port internal yang diperlukan).

---

## 6) Saran Tahap Migrasi Owner-Friendly

1) **Single node k3s** (yang sudah ada sekarang)
2) Tambah 1 worker node (jadi 2 node)
3) Pindahkan worker berat ke worker node (label/taint) jika perlu
4) Tambah autoscaling (KEDA/HPA) jika sudah siap

