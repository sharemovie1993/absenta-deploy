# Laporan Pemeriksaan dan Perbaikan Script Update App Server

## 1. Pendahuluan
Berdasarkan permintaan untuk memeriksa dan memperbaiki script update app server agar proses pull tidak terhambat oleh perubahan lokal, saya telah melakukan pemeriksaan pada file `update_app_server.sh`.

## 2. Temuan
- Script `update_app_server.sh` sebelumnya langsung melakukan `git pull` tanpa memastikan status direktori kerja bersih.
- Jika terdapat perubahan lokal (file yang diedit atau dibuat di server produksi) pada file yang dilacak git, proses `git pull` akan gagal atau menyebabkan konflik merge.

## 3. Tindakan Perbaikan
Saya telah memodifikasi file `c:\Users\SERVER-DELL\Documents\Projek\absenta-deploy\update_app_server.sh` dengan menambahkan perintah `git reset --hard` sebelum `git pull` pada bagian update backend dan frontend.

Langkah-langkah yang ditambahkan:
1. **Backup .env**: Script sudah memiliki mekanisme backup `.env`, sehingga aman dari reset jika file tersebut tidak di-track git (atau akan direstore setelah reset).
2. **Reset Hard**: Menambahkan `git reset --hard` untuk menghapus semua perubahan lokal pada file yang dilacak git.
3. **Fetch & Pull**: Melakukan `git fetch --all` dan `git pull` untuk mengambil versi terbaru dari repository.

## 4. Hasil Kode (Snippet)
Berikut adalah perubahan logika yang diterapkan (berlaku untuk Backend dan Frontend):

```bash
if [ -d ".git" ]; then
  echo "Mereset perubahan lokal..."
  git reset --hard  # <--- Perintah baru ditambahkan
  git fetch --all
  git pull
fi
```

## 5. Kesimpulan
Script `update_app_server.sh` sekarang akan secara otomatis menghapus perubahan lokal pada file yang dilacak git sebelum melakukan update, memastikan proses deployment berjalan lancar tanpa hambatan konflik file.
