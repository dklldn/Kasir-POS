# Cashier Mobile - Emulator / POS

Versi ini memakai penyimpanan lokal SQLite-like melalui SharedPreferences sehingga produk, transaksi, shift, karyawan, stok dan audit tidak hilang saat aplikasi ditutup.

## Login demo
- Owner: `123456`
- Kasir: `111111`

## Fitur
- Tablet kasir
- Login PIN karyawan
- Role Owner / Manager / Kasir
- Manajemen shift, buka/tutup shift
- Transaksi dan pembayaran
- Stok otomatis berkurang setelah transaksi berhasil
- Produk/makanan tersimpan permanen di perangkat
- Ubah stok dengan catatan dan audit siapa/kapan
- Cetak struk via dialog printer Android
- Otorisasi pembukaan cash drawer manual
- Laporan penjualan, stok rendah, riwayat transaksi
- Riwayat aktivitas karyawan

## Jalankan
```powershell
flutter clean
flutter pub get
flutter run
```

### Printer & cash drawer
Emulator dapat menguji pembuatan/preview struk melalui dialog printer Android. Cash drawer fisik tidak dapat diuji tanpa printer POS yang memiliki port/pulse drawer. Otorisasi dan pencatatan pembukaan laci sudah tersedia.

### Multi-device
Mode offline/local menyimpan data per perangkat. Untuk pantau transaksi dari banyak HP secara real-time diperlukan Firebase/Firestore dan konfigurasi project Firebase (`google-services.json`). Struktur aplikasi sengaja memisahkan store agar sinkronisasi cloud dapat ditambahkan tanpa mengubah alur kasir.
