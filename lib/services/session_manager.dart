import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mengelola state sesi yang bersifat global:
/// - navigator & scaffold messenger key agar bisa dipakai dari service
/// - pembersihan token lokal
/// - redirect otomatis ke login saat token kedaluwarsa (401)
class SessionManager {
  SessionManager._();

  static final navigatorKey = GlobalKey<NavigatorState>();
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  static bool _expiredHandled = false;

  /// Hapus token & data lokal tanpa memanggil API.
  static Future<void> clearLocal() async {
    await const FlutterSecureStorage().deleteAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  /// Dipanggil saat API mengembalikan 401.
  static Future<void> handleExpired() async {
    if (_expiredHandled) return;
    _expiredHandled = true;

    await clearLocal();

    navigatorKey.currentState?.pushNamedAndRemoveUntil(
      '/login',
      (route) => false,
    );
    messengerKey.currentState?.showSnackBar(
      const SnackBar(
        content: Text('Sesi Anda sudah berakhir. Silakan login kembali.'),
      ),
    );
  }

  /// Reset guard setelah login berhasil / logout manual.
  static void reset() {
    _expiredHandled = false;
  }
}
