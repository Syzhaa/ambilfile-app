# AmbilFile App

Aplikasi berbagi file AmbilFile — Android & Desktop. Backend: [syzhaa-file](https://github.com/Syzhaa/syzhaa-file) · Web: https://ambilfile.web.id

## Struktur

```
ambilfile-app/
├── mobile/    → Flutter Android (arm64 APK)
└── desktop/   → Flutter Windows / Linux / macOS
```

Kedua folder berbagi kode Dart yang sama (`lib/`), beda di platform & plugin khusus.

## Fitur

- Buat room + gabung via PIN (tanpa login, kuota 1 GB/room)
- Login Google → room terhubung akun (kuota 2 GB), dashboard, bottom nav (Beranda / Ruangan / API Key / Akun)
- Upload chunked 5 MB + resume otomatis + retry, progres per-byte + kecepatan Mbps
- Download dengan dialog progres mulus + tombol Batal
- Folder: buat / navigasi / hapus, upload ke dalam folder
- API key: minta akses admin, buat/hapus key

## Build Mobile (Android)

```bash
cd mobile
flutter pub get
flutter build apk --release --target-platform android-arm64
# hasil: build/app/outputs/flutter-apk/app-release.apk
```

## Build Desktop

### Windows

```powershell
cd desktop
flutter config --enable-windows-desktop
flutter pub get
flutter build windows --release
# hasil: build\windows\x64\runner\Release\
```

### Linux

```bash
cd desktop
sudo apt install clang cmake ninja-build libgtk-3-dev liblzma-dev
flutter config --enable-linux-desktop
flutter pub get
flutter build linux --release
# hasil: build/linux/x64/release/bundle/
```

### macOS

```bash
cd desktop
flutter config --enable-macos-desktop
flutter pub get
flutter build macos --release
```

## Catatan Desktop

- Login: browser terbuka → login Google → copy token dari halaman web → paste di dialog aplikasi (deep link `ambilfile://` hanya untuk mobile).
- Foreground service & wakelock hanya aktif di Android; di desktop upload jalan di proses utama.
- File terunduh masuk folder **Downloads**.
- Slot khusus fitur Windows: tambah kode di `desktop/` dengan cek `Platform.isWindows` — folder `mobile/` tidak ikut berubah.
