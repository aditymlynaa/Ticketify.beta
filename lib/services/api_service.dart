import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_manager.dart';

class ApiService {
  // Override saat build/run, contoh:
  // flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.1.9:8000/api',
  );

  static const _storage = FlutterSecureStorage();
  static const _timeout = Duration(seconds: 20);

  // --- HELPER STORAGE & HEADERS ---
  static Future<void> saveToken(String token) async {
    await _storage.write(key: 'auth_token', value: token);
  }

  static Future<String?> getToken() async {
    return await _storage.read(key: 'auth_token');
  }

  static Future<void> deleteToken() async {
    await _storage.delete(key: 'auth_token');
  }

  static Future<Map<String, String>> _getHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Tangani token kedaluwarsa secara global.
  static Future<void> _checkAuth(int statusCode) async {
    if (statusCode == 401) {
      await SessionManager.handleExpired();
    }
  }

  /// Bentuk response error yang seragam untuk semua method.
  static Map<String, dynamic> _error(String message) {
    return {
      'status': 500,
      'data': {'message': message},
    };
  }

  /// Simpan identitas dasar user agar layar lain (mis. chat) tahu siapa
  /// pengguna yang sedang login tanpa harus memanggil /me lagi.
  static Future<void> _persistUser(dynamic user) async {
    if (user is! Map) return;

    final prefs = await SharedPreferences.getInstance();
    final role = user['role'];
    final id = user['id'];
    final name = user['name'];

    if (role != null) await prefs.setString('role', role.toString());
    if (id != null) await prefs.setString('user_id', id.toString());
    if (name != null) await prefs.setString('user_name', name.toString());
  }

  /// Cek apakah token tersimpan masih bisa dipakai saat aplikasi dibuka.
  ///
  /// Sengaja tidak memakai [_checkAuth] supaya tidak memicu redirect global
  /// saat splash screen sedang menentukan halaman awal.
  static Future<bool> hasValidSession() async {
    String? token;

    try {
      // Timeout kecil supaya splash tidak menggantung jika penyimpanan
      // aman bermasalah di platform tertentu.
      token = await getToken().timeout(const Duration(seconds: 2));
    } catch (_) {
      return false;
    }

    if (token == null || token.isEmpty) return false;

    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl/me'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(_timeout);

      if (response.statusCode == 401) {
        await SessionManager.clearLocal();
        return false;
      }

      // Status lain (mis. 500) tetap dianggap punya sesi; layar dashboard
      // akan menampilkan pesan error dan user bisa logout manual.
      return true;
    } catch (_) {
      // Server belum terjangkau: tetap masuk agar user tidak dipaksa login
      // ulang hanya karena jaringan sedang bermasalah.
      return true;
    }
  }

  /// Ubah path lampiran relatif (/storage/...) menjadi URL lengkap sesuai
  /// host API yang sedang dipakai.
  static String absoluteUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }

    final uri = Uri.parse(baseUrl);
    final origin = '${uri.scheme}://${uri.authority}';
    return path.startsWith('/') ? '$origin$path' : '$origin/$path';
  }

  /// Ambil array tiket dari berbagai bentuk response yang mungkin dipakai.
  static List<dynamic> _extractTicketList(Map body) {
    final raw = body['data'];
    if (raw is List) return raw;
    if (raw is Map && raw['data'] is List) return raw['data'] as List;
    if (body['tickets'] is List) return body['tickets'] as List;
    return const [];
  }

  // --- AUTHENTICATION ---
  // 1. Auth: Login
  static Future<Map<String, dynamic>> login(
    String email,
    String password,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/login'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(_timeout);

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        String? token =
            data['token'] ??
            data['access_token'] ??
            data['data']?['token'] ??
            data['data']?['access_token'];

        if (token != null) {
          await saveToken(token);
        }

        // Simpan identitas user agar bisa dibaca di layar lain.
        await _persistUser(data['user'] ?? data['data']?['user']);

        SessionManager.reset();
      }
      return {'status': response.statusCode, 'data': data};
    } catch (e) {
      return _error('Gagal terhubung ke server: $e');
    }
  }

  // 2. Auth: Logout
  static Future<void> logout() async {
    try {
      final headers = await _getHeaders();
      await http
          .post(Uri.parse('$baseUrl/logout'), headers: headers)
          .timeout(_timeout);
    } catch (e) {
      debugPrint('Error logging out from server: $e');
    } finally {
      await SessionManager.clearLocal();
      SessionManager.reset();
    }
  }

  // --- USER & DASHBOARD ---
  // 3. User: Get Profile (/me)
  static Future<Map<String, dynamic>> getProfile() async {
    try {
      final headers = await _getHeaders();
      final response = await http
          .get(Uri.parse('$baseUrl/me'), headers: headers)
          .timeout(_timeout);

      await _checkAuth(response.statusCode);

      return {'status': response.statusCode, 'data': jsonDecode(response.body)};
    } catch (e) {
      return _error('Gagal memuat profil: $e');
    }
  }

  // 4. Dashboard: Get Statistics
  static Future<Map<String, dynamic>> getStatistics() async {
    try {
      final headers = await _getHeaders();
      final response = await http
          .get(Uri.parse('$baseUrl/dashboard/statistics'), headers: headers)
          .timeout(_timeout);

      await _checkAuth(response.statusCode);

      return {'status': response.statusCode, 'data': jsonDecode(response.body)};
    } catch (e) {
      return _error('Gagal memuat statistik: $e');
    }
  }

  // --- TICKET SYSTEM ---
  // 5. Create Ticket
  static Future<Map<String, dynamic>> createTicket({
    required String title,
    required String description,
    required String priority,
    String? category,
    String? locationAddress,
    String? latitude,
    String? longitude,
  }) async {
    try {
      final headers = await _getHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/tickets'),
            headers: headers,
            body: jsonEncode({
              'title': title,
              'description': description,
              'priority': priority,
              'category': category,
              'location_address': locationAddress,
              'latitude': latitude,
              'longitude': longitude,
            }),
          )
          .timeout(_timeout);

      await _checkAuth(response.statusCode);

      return {'status': response.statusCode, 'data': jsonDecode(response.body)};
    } catch (e) {
      return _error('Gagal membuat tiket: $e');
    }
  }

  // 6. Get List Tiket (dengan pagination)
  static Future<Map<String, dynamic>> getTickets({
    String? search,
    String? status,
    String? category,
    String? assigned,
    int page = 1,
    int perPage = 15,
  }) async {
    try {
      final headers = await _getHeaders();

      final Map<String, String> queryParams = {
        'page': '$page',
        'per_page': '$perPage',
      };
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (status != null && status.isNotEmpty) queryParams['status'] = status;
      if (category != null && category.isNotEmpty) {
        queryParams['category'] = category;
      }
      if (assigned != null && assigned.isNotEmpty) {
        queryParams['assigned'] = assigned;
      }

      final uri = Uri.parse('$baseUrl/tickets')
          .replace(queryParameters: queryParams);

      final response = await http.get(uri, headers: headers).timeout(_timeout);

      await _checkAuth(response.statusCode);

      final decoded = json.decode(response.body);

      if (response.statusCode != 200 || decoded is! Map) {
        return {
          'status': response.statusCode,
          'data': decoded,
          'meta': const <String, dynamic>{},
        };
      }

      return {
        'status': response.statusCode,
        'data': _extractTicketList(decoded),
        'meta': decoded['meta'] is Map
            ? Map<String, dynamic>.from(decoded['meta'] as Map)
            : const <String, dynamic>{},
        'message': decoded['message'],
      };
    } catch (e) {
      return _error('Gagal memuat daftar tiket: $e');
    }
  }

  // 6b. Ubah status tiket (khusus admin)
  static Future<Map<String, dynamic>> updateTicketStatus(
    String code,
    String status,
  ) async {
    try {
      final headers = await _getHeaders();
      final response = await http
          .patch(
            Uri.parse('$baseUrl/tickets/$code/status'),
            headers: headers,
            body: jsonEncode({'status': status}),
          )
          .timeout(_timeout);

      await _checkAuth(response.statusCode);

      return {'status': response.statusCode, 'data': jsonDecode(response.body)};
    } catch (e) {
      return _error('Gagal mengubah status tiket: $e');
    }
  }

  // 7. Get Detail Tiket beserta balasan chat
  static Future<Map<String, dynamic>> getTicketDetail(String code) async {
    try {
      final headers = await _getHeaders();
      final response = await http
          .get(Uri.parse('$baseUrl/tickets/$code'), headers: headers)
          .timeout(_timeout);

      await _checkAuth(response.statusCode);

      return {'status': response.statusCode, 'data': jsonDecode(response.body)};
    } catch (e) {
      return _error('Gagal memuat detail tiket: $e');
    }
  }

  // 8. Send Reply (Kirim Balasan Chat & Update Status)
  static Future<Map<String, dynamic>> sendReply(
    String code,
    String content, {
    String? status,
    bool isInternal = false,
  }) async {
    try {
      final headers = await _getHeaders();

      final body = <String, dynamic>{'content': content};
      if (status != null) body['status'] = status;
      if (isInternal) body['is_internal'] = true;

      final response = await http
          .post(
            Uri.parse('$baseUrl/tickets/$code/reply'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(_timeout);

      await _checkAuth(response.statusCode);

      return {'status': response.statusCode, 'data': jsonDecode(response.body)};
    } catch (e) {
      return _error('Gagal mengirim balasan: $e');
    }
  }

  // 9. Auth: Register
  static Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
    required String passwordConfirmation,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/register'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'name': name,
              'email': email,
              'password': password,
              'password_confirmation': passwordConfirmation,
            }),
          )
          .timeout(_timeout);

      final data = jsonDecode(response.body);

      if (response.statusCode == 201) {
        // Simpan token & identitas user jika otomatis auto-login setelah register
        final token = data['data']?['token'];
        if (token != null) await saveToken(token);
        await _persistUser(data['data']?['user']);

        SessionManager.reset();
      }

      return {'status': response.statusCode, 'data': data};
    } catch (e) {
      return _error('Gagal mendaftar: $e');
    }
  }

  // 10. Ambil daftar notifikasi
  static Future<Map<String, dynamic>> getNotifications() async {
    try {
      final headers = await _getHeaders();
      final response = await http
          .get(Uri.parse('$baseUrl/notifications'), headers: headers)
          .timeout(_timeout);

      await _checkAuth(response.statusCode);

      return {'status': response.statusCode, 'data': jsonDecode(response.body)};
    } catch (e) {
      return _error('Gagal memuat notifikasi: $e');
    }
  }

  // 11. Tandai notifikasi sebagai 'read' (sudah dibaca)
  static Future<Map<String, dynamic>> markNotificationAsRead(String id) async {
    try {
      final headers = await _getHeaders();
      final response = await http
          .post(Uri.parse('$baseUrl/notifications/$id/read'), headers: headers)
          .timeout(_timeout);

      await _checkAuth(response.statusCode);

      return {'status': response.statusCode, 'data': jsonDecode(response.body)};
    } catch (e) {
      return _error('Gagal menandai notifikasi: $e');
    }
  }

  // 12. Ambil jumlah notifikasi yang belum dibaca (untuk badge lonceng)
  static Future<Map<String, dynamic>> getUnreadCount() async {
    try {
      final headers = await _getHeaders();
      final response = await http
          .get(
            Uri.parse('$baseUrl/notifications/unread-count'),
            headers: headers,
          )
          .timeout(_timeout);

      await _checkAuth(response.statusCode);

      return {'status': response.statusCode, 'data': jsonDecode(response.body)};
    } catch (e) {
      return _error('Gagal memuat jumlah notifikasi: $e');
    }
  }

  // 13. Tandai semua notifikasi sebagai sudah dibaca
  static Future<Map<String, dynamic>> markAllNotificationsAsRead() async {
    try {
      final headers = await _getHeaders();
      final response = await http
          .post(Uri.parse('$baseUrl/notifications/read-all'), headers: headers)
          .timeout(_timeout);

      await _checkAuth(response.statusCode);

      return {'status': response.statusCode, 'data': jsonDecode(response.body)};
    } catch (e) {
      return _error('Gagal menandai semua notifikasi: $e');
    }
  }

  // 14. Metadata tiket: kategori, target SLA, dan daftar admin.
  static Future<Map<String, dynamic>> getTicketMeta() async {
    try {
      final headers = await _getHeaders();
      final response = await http
          .get(Uri.parse('$baseUrl/tickets/meta'), headers: headers)
          .timeout(_timeout);

      await _checkAuth(response.statusCode);

      return {'status': response.statusCode, 'data': jsonDecode(response.body)};
    } catch (e) {
      return _error('Gagal memuat metadata tiket: $e');
    }
  }

  // 15. Profil: perbarui nama, telepon, departemen.
  static Future<Map<String, dynamic>> updateProfile({
    required String name,
    String? phone,
    String? department,
  }) async {
    try {
      final headers = await _getHeaders();
      final response = await http
          .patch(
            Uri.parse('$baseUrl/profile'),
            headers: headers,
            body: jsonEncode({
              'name': name,
              'phone': phone,
              'department': department,
            }),
          )
          .timeout(_timeout);

      await _checkAuth(response.statusCode);

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data is Map) {
        await _persistUser(data['data']);
      }

      return {'status': response.statusCode, 'data': data};
    } catch (e) {
      return _error('Gagal memperbarui profil: $e');
    }
  }

  // 16. Profil: ganti password.
  static Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  }) async {
    try {
      final headers = await _getHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/profile/password'),
            headers: headers,
            body: jsonEncode({
              'current_password': currentPassword,
              'password': password,
              'password_confirmation': passwordConfirmation,
            }),
          )
          .timeout(_timeout);

      await _checkAuth(response.statusCode);

      return {'status': response.statusCode, 'data': jsonDecode(response.body)};
    } catch (e) {
      return _error('Gagal mengganti password: $e');
    }
  }

  // 17. Lupa password: minta kode verifikasi.
  static Future<Map<String, dynamic>> forgotPassword(String email) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/forgot-password'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'email': email}),
          )
          .timeout(_timeout);

      return {'status': response.statusCode, 'data': jsonDecode(response.body)};
    } catch (e) {
      return _error('Gagal mengirim kode verifikasi: $e');
    }
  }

  // 18. Lupa password: verifikasi kode & set password baru.
  static Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String code,
    required String password,
    required String passwordConfirmation,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/reset-password'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'email': email,
              'code': code,
              'password': password,
              'password_confirmation': passwordConfirmation,
            }),
          )
          .timeout(_timeout);

      return {'status': response.statusCode, 'data': jsonDecode(response.body)};
    } catch (e) {
      return _error('Gagal mereset password: $e');
    }
  }

  // 19. Beri penilaian CSAT untuk tiket yang sudah selesai.
  static Future<Map<String, dynamic>> submitCsat(
    String code, {
    required int rating,
    String? comment,
  }) async {
    try {
      final headers = await _getHeaders();
      final response = await http
          .post(
            Uri.parse('$baseUrl/tickets/$code/csat'),
            headers: headers,
            body: jsonEncode({'rating': rating, 'comment': comment}),
          )
          .timeout(_timeout);

      await _checkAuth(response.statusCode);

      return {'status': response.statusCode, 'data': jsonDecode(response.body)};
    } catch (e) {
      return _error('Gagal menyimpan penilaian: $e');
    }
  }

  // 20. Tetapkan / lepas penanggung jawab tiket (admin).
  static Future<Map<String, dynamic>> assignTicket(
    String code,
    int? assignedTo,
  ) async {
    try {
      final headers = await _getHeaders();
      final response = await http
          .patch(
            Uri.parse('$baseUrl/tickets/$code/assign'),
            headers: headers,
            body: jsonEncode({'assigned_to': assignedTo}),
          )
          .timeout(_timeout);

      await _checkAuth(response.statusCode);

      return {'status': response.statusCode, 'data': jsonDecode(response.body)};
    } catch (e) {
      return _error('Gagal menetapkan penanggung jawab: $e');
    }
  }

  // 21. Unggah lampiran tiket / balasan.
  static Future<Map<String, dynamic>> uploadAttachment(
    String code, {
    required List<int> bytes,
    required String filename,
    String? replyId,
  }) async {
    try {
      final token = await getToken();
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/tickets/$code/attachments'),
      );

      request.headers['Accept'] = 'application/json';
      if (token != null && token.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );
      if (replyId != null) request.fields['reply_id'] = replyId;

      final streamed = await request.send().timeout(
        const Duration(seconds: 60),
      );
      final response = await http.Response.fromStream(streamed);

      await _checkAuth(response.statusCode);

      return {'status': response.statusCode, 'data': jsonDecode(response.body)};
    } catch (e) {
      return _error('Gagal mengunggah lampiran: $e');
    }
  }
}
