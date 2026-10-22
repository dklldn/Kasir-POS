# Panglima Laut POS

Aplikasi kasir berbasis Flutter dan Firebase untuk mendukung operasional Rumah Makan Panglima Laut.

## Fitur Utama

- Login kasir menggunakan PIN aplikasi.
- Firebase Authentication untuk sesi Owner dan Cloud Firestore untuk penyimpanan data.
- Pengelolaan akun dan hak akses karyawan oleh Owner.
- Transaksi penjualan dan pengelolaan pesanan atau tiket tersimpan.
- Cetak struk menggunakan printer thermal Bluetooth.
- Penyimpanan pilihan printer dan upaya penyambungan ulang saat aplikasi dibuka.
- Pengelolaan laci kasir sesuai hak akses.
- Laporan penjualan, kategori produk, dan tutup shift.

## Hak Akses Karyawan

Owner dapat mengatur hak akses masing-masing karyawan, meliputi:

- Membuat transaksi.
- Melihat dan mencetak struk.
- Membatalkan struk.
- Membuka laci kasir.
- Menambah, mengedit, dan menghapus barang.
- Mengubah stok.
- Melihat laporan.
- Menutup shift.
- Mengelola printer dan koneksi Bluetooth melalui izin `managePrinter`.

Menu **Kelola** hanya tersedia untuk Owner. Akses ke halaman manajemen juga harus dibatasi untuk akun Owner. Role Owner memiliki hak akses penuh, sedangkan hak akses Manager dan Kasir dapat disesuaikan oleh Owner.

## Audit Transaksi dan Stok

- Pembatalan struk dicatat dengan status `VOID`.
- Alasan pembatalan dan pelaku dicatat untuk kebutuhan audit.
- Stok dikembalikan saat transaksi dibatalkan sesuai implementasi aplikasi.
- Stok awal dapat bernilai nol.
- Batas stok maksimum per produk bersifat opsional.
- Peringatan stok dapat ditampilkan ketika stok mencapai batas yang ditentukan, jika batas maksimum lebih dari nol.
- Catatan tutup shift bersifat opsional.

## Firebase

Aplikasi menggunakan Firebase Authentication dan Cloud Firestore. Konfigurasi Firebase harus mengarah ke proyek yang dikelola pemilik aplikasi.

Pastikan aturan keamanan Firestore membatasi akses berdasarkan autentikasi dan hak akses yang sesuai. Jangan memasukkan kredensial privat atau rahasia server ke repositori publik.

Dokumentasi terkait:

- `README-FIREBASE-OWNER-AUTH.md`
- `README-FIREBASE-SYNC.md`

## Printer Bluetooth dan Laci Kasir

- Aplikasi menyimpan pilihan printer terakhir sesuai implementasi proyek.
- Saat aplikasi dibuka, aplikasi dapat meminta izin Bluetooth yang diperlukan dan mencoba menyambung ulang ke printer tersimpan.
- Penyambungan ulang hanya dapat berhasil apabila printer tersedia, dapat dijangkau, dan izin Bluetooth telah diberikan.
- Jika printer mati atau tidak terjangkau, nyalakan printer lalu buka menu Printer untuk mencari dan menghubungkannya kembali.
- Pembukaan laci kasir mengikuti alur transaksi dan hak akses yang dikonfigurasi.
- Cetak struk dan pembukaan laci perlu diuji pada perangkat Android serta printer yang digunakan.

## Logo Struk

Proyek menyediakan dukungan logo Rumah Makan Panglima Laut pada struk printer POS dan PDF sesuai implementasi yang tersedia.

## Persyaratan Pengembangan

- Flutter SDK
- Android SDK
- Konfigurasi Firebase untuk aplikasi

## Menjalankan Proyek di Windows

Buka PowerShell di direktori proyek yang berisi `pubspec.yaml`, lalu jalankan:

```powershell
flutter clean
flutter pub get
flutter analyze
flutter build apk
```

Jika build gagal, periksa pesan error Flutter, konfigurasi Gradle, versi plugin, dan konfigurasi Firebase.

## Catatan Build Android

Konfigurasi proyek ini sebelumnya menggunakan Android Gradle Plugin 8.12.1 dan Gradle 8.14. Verifikasi konfigurasi aktual dan kompatibilitas dependensi jika memperbarui Flutter atau plugin Android.

## Identitas Repositori

Nama aplikasi dan dokumentasi proyek ini adalah **Panglima Laut POS**. Mengubah README tidak otomatis mengubah kepemilikan atau remote Git. Untuk memakai repositori GitHub milik sendiri, pastikan remote `origin` menunjuk ke repositori yang benar dan repositori tersebut sudah dibuat serta dapat diakses.


## Sebelum Publikasi
Baca `PUBLISH_CHECKLIST_ID.md`. ZIP ini adalah paket persiapan/review, bukan jaminan aplikasi telah lolos audit keamanan atau siap diunggah. Firestore Rules masih menolak akses sampai UID Owner diganti dan rules dipublikasikan. Rilis Android juga membutuhkan keystore pribadi.
