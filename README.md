# Flutter Ticket App

Aplikasi mobile helpdesk/ticketing untuk Flutter, terhubung ke backend Laravel
(`api-indihome-support`) menggunakan Laravel Sanctum.

## Fitur

- Login & registrasi (token disimpan di `flutter_secure_storage`)
- Dashboard user/admin (statistik status tiket & rata-rata penanganan)
- Daftar tiket dengan pencarian, filter status, dan badge pesan baru
- Buat tiket baru (judul, prioritas, deskripsi)
- Detail tiket + chat balasan; admin dapat mengubah status
- Notifikasi in-app

## Prasyarat

- Flutter SDK (Dart 3.13+)
- Backend Laravel sudah berjalan dan database sudah dimigrasikan

## Konfigurasi API

Base URL diambil dari compile-time environment variable. Default-nya
`http://192.168.-.-:8000/api`.

```bash
# HP fisik (gunakan IP LAN komputer yang menjalankan Laravel)
flutter run --dart-define=API_BASE_URL=http://192.168.1.-:8000/api

# Android emulator
flutter run --dart-define=API_BASE_URL=http://10.0.2.-:8000/api

# iOS simulator / desktop / web
flutter run --dart-define=API_BASE_URL=http://localhost:8000/api
```

Pastikan backend dijalankan dengan host yang bisa diakses perangkat:

```bash
php artisan serve --host=0.0.0.0 --port=8000
```

## Menjalankan

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://192.168.1.9:8000/api
```

## Pengujian & analisis

```bash
flutter analyze
flutter test
```

## Struktur

```text
lib/
  main.dart                 # MaterialApp, routing, global key sesi
  screens/                  # Halaman UI
  services/
    api_service.dart        # Semua request HTTP + penanganan 401
    session_manager.dart    # Pembersihan sesi & redirect ke login
  utils/
    date_formatter.dart     # Format tanggal Indonesia
```

## Catatan backend

Migrasi terbaru menambahkan prioritas `critical`, menandai balasan admin
(`is_admin`), dan mengirim tanggal dalam format ISO-8601. Jalankan:

```bash
php artisan migrate
```
