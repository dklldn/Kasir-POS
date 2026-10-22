# Checklist publikasi — Panglima Laut POS

Dokumen ini tidak menyatakan aplikasi otomatis aman/siap rilis. Selesaikan semua langkah berikut sebelum dipakai untuk transaksi nyata atau diunggah ke toko aplikasi.

## 1. Firebase wajib diamankan
- Firebase Authentication > Sign-in method: aktifkan Email/Password hanya jika memang dipakai.
- Buat akun Owner khusus dan lindungi password-nya.
- Salin UID Owner dari Authentication > Users.
- Ganti `OWNER_UID_DARI_FIREBASE` pada `firestore.rules` dengan UID Owner yang benar.
- Publikasikan rules tersebut di Firebase Console > Firestore Database > Rules. Aturan saat ini sengaja menolak akses sampai placeholder diganti.
- Jangan pernah menggunakan aturan `allow read, write: if true`.
- Pastikan hanya Owner yang perlu mengakses dokumen `pos_data/main_store`. Dokumen ini berisi data POS termasuk data karyawan dan transaksi; jangan membagikan akun Owner.
- Batasi API key Firebase melalui Google Cloud Console bila sesuai, pantau penggunaan, dan siapkan backup data.
- `google-services.json` adalah konfigurasi klien Firebase, bukan rahasia server. Jangan pernah memasukkan service-account JSON, private key, password, atau kredensial ke ZIP/repo publik.

## 2. Siapkan tanda tangan rilis Android
Jangan gunakan debug keystore untuk publikasi. Buat keystore pribadi dan simpan di tempat aman, jangan kirim ke orang lain atau commit ke Git. Di folder `android/`, buat `key.properties` berdasarkan format berikut dan isi dengan nilai milik Anda:

```properties
storePassword=PASSWORD_KEYSTORE_ANDA
keyPassword=PASSWORD_KEY_ANDA
keyAlias=ALIAS_KEY_ANDA
storeFile=PATH_KE_KEYSTORE_ANDA
```

`key.properties` dan file keystore diabaikan oleh `.gitignore`. Jangan menaruh nilai contoh di atas sebagai kredensial sungguhan. Simpan cadangan keystore dan password secara aman; kehilangan kunci dapat menghambat pembaruan aplikasi.

## 3. Uji sebelum rilis
Dari folder `fix29`:

```powershell
flutter clean
flutter pub get
flutter analyze
flutter test
flutter build appbundle --release
```

Build rilis harus ditandatangani dengan keystore rilis Anda. Jika belum membuat `android/key.properties` dan keystore, jangan unggah hasil build. Uji login Owner, akses kasir berdasarkan peran, transaksi, pembatalan, stok, tutup shift, printer, laci kasir, dan pemulihan data di perangkat uji. Pastikan sinkronisasi Firestore berhasil serta data dapat dipulihkan dari backup.

## 4. Batasan yang perlu diketahui
- Proyek menyimpan banyak data POS dalam satu dokumen Firestore `pos_data/main_store`; dokumen Firestore memiliki batas ukuran 1 MiB. Pantau pertumbuhan data dan rencanakan pemisahan transaksi ke koleksi tersendiri sebelum data membesar.
- Sinkronisasi yang ada bukan sinkronisasi multi-perangkat real-time.
- Build Web/iOS perlu konfigurasi Firebase khusus platform dan pengujian terpisah. Panduan ini berfokus pada Android.
- Perubahan nama aplikasi yang terlihat tidak mengubah package ID Android `com.tutu.cashier`, karena package ID merupakan identitas aplikasi yang sudah digunakan.
