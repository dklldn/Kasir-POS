PERBAIKAN SINKRONISASI FIREBASE (minimal)

Perubahan:
- Menambahkan firebase_core dan cloud_firestore.
- Aplikasi mencoba menginisialisasi Firebase saat startup.
- Data POS disimpan ke lokal terlebih dahulu, lalu disinkronkan ke Cloud Firestore.
- Saat pertama kali, jika dokumen cloud belum ada, data lokal diunggah. Jika dokumen sudah ada, data cloud dimuat ke perangkat.
- Jika Firebase/internet gagal, aplikasi tetap berjalan lokal dan menulis log di Debug Console.

WAJIB sebelum menjalankan:
1. Buka Firebase Console > project cashier-a863c > Project settings > Your apps.
2. Unduh file google-services.json untuk aplikasi Android dengan package name: com.tutu.cashier.
3. Letakkan file di: fix29/android/app/google-services.json (folder app, bukan folder android utama).
4. Firebase Console > Build > Firestore Database: buat database bila belum ada.
5. Untuk pengujian awal, atur Firestore Rules agar aplikasi dapat menulis hanya sesuai skema keamanan yang Anda rencanakan. Jangan biarkan rules terbuka (allow read, write: if true) untuk produksi.
6. Dari folder fix29 jalankan:
   flutter clean
   flutter pub get
   flutter run

Catatan penting:
- firebase.json bukan file yang diperlukan untuk koneksi runtime Flutter ini. Jangan menaruh konfigurasi "flutter" ke firebase.json.
- Koneksi ini memakai satu dokumen Firestore: pos_data/main_store. Cocok untuk POS kecil, tetapi dokumen Firestore memiliki batas 1 MiB. Jika data transaksi makin banyak, sebaiknya migrasi ke koleksi terpisah.
- Login PIN tetap lokal pada perangkat; data karyawan/izin dan hash PIN ikut tersinkron dalam dokumen. Batasi akses Firestore melalui aturan keamanan yang sesuai.
- Sinkronisasi saat ini bukan mekanisme multi-perangkat real-time; unggah dilakukan saat aplikasi menyimpan perubahan.
