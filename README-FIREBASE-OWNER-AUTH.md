PENGATURAN FIREBASE OWNER — POS

Perubahan aplikasi:
- Login Firebase Owner diminta saat belum ada sesi Firebase pada perangkat. Password hanya diketik di layar konfigurasi dan tidak ditanam ke source/ZIP.
- Setelah sesi Firebase tersimpan, login operasional POS tetap menggunakan PIN lokal.
- Sinkronisasi tetap menggunakan dokumen pos_data/main_store.
- google-services.json Android ditambahkan untuk package com.tutu.cashier.

WAJIB sebelum uji:
1. Pastikan Firebase Console > Authentication > Sign-in method > Email/Password aktif dan akun Owner ada di Authentication > Users.
2. Buka Authentication > Users, salin UID akun Owner (bukan email).
3. Edit firestore.rules: ganti OWNER_UID_DARI_FIREBASE dengan UID persis milik Owner. Jangan gunakan tanda kurung siku; pertahankan tanda petik.
4. Firebase Console > Firestore Database > Rules, tempel isi firestore.rules yang sudah diubah, lalu Publish. Rules hanya mengizinkan UID Owner untuk membaca/menulis pos_data/main_store; dokumen lain ditolak.
5. Jalankan dari folder fix29: flutter clean, flutter pub get, flutter run.
6. Masuk sekali dengan email/password Firebase Owner. Setelah itu login kasir sehari-hari tetap PIN.

PENTING:
- Jangan bagikan password Firebase. Jangan menaruh password di kode, .env yang ikut ZIP, atau Firestore Rules.
- Akun Firebase Owner yang sama berarti perangkat tersebut mendapat akses ke seluruh dokumen POS utama. Lindungi perangkat Owner.
- Akun Firebase tidak otomatis membuat akun PIN Owner di POS; setup PIN lokal tetap dilakukan di layar POS bila data karyawan lokal kosong.
- Pastikan Firestore Database sudah dibuat. Pengujian build perlu dilakukan pada komputer yang memiliki Flutter SDK dan internet.

CATATAN PUBLIKASI GITHUB:
- Jangan pernah commit password Owner, private key, file service-account Firebase, atau signing key Android.
- android/app/google-services.json adalah konfigurasi klien Firebase (bukan private key server), dipertahankan agar setup Android tetap dikenali. Sebelum repositori dibuat publik, batasi API key melalui Google Cloud Console bila memungkinkan dan pastikan Firestore Security Rules hanya memberi akses kepada UID Owner yang sah.
- firestore.rules di proyek ini masih memakai placeholder OWNER_UID_DARI_FIREBASE dan secara default menolak akses sampai diganti dengan UID Owner yang benar. Jangan menganggap placeholder sudah siap untuk produksi.
- File hasil generate iOS/local telah dikeluarkan dari arsip; Flutter dapat membuatnya ulang sesuai kebutuhan.

