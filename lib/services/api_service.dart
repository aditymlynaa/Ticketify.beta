import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Sesuaikan IP berikut dengan IPv4 Laptop kamu
  static const String baseUrl = 'http://192.168.1.8:8000/api';
  
  static const _storage = FlutterSecureStorage();

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

  // --- AUTHENTICATION ---
  // 1. Auth: Login
  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'email': email, 'password': password}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        String? token = data['token'] ?? 
                        data['access_token'] ?? 
                        data['data']?['token'] ?? 
                        data['data']?['access_token'];

        if (token != null) {
          await saveToken(token);
        }

        // Simpan role ke SharedPreferences agar bisa dibaca di TicketDetailScreen
        final role = data['user']?['role'] ?? data['data']?['user']?['role'];
        if (role != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('role', role.toString());
        }
      }
      return {'status': response.statusCode, 'data': data};
    } catch (e) {
      return {'status': 500, 'data': {'message': 'Gagal terhubung ke server: $e'}};
    }
  }

  // 2. Auth: Logout
  static Future<void> logout() async {
    try {
      final headers = await _getHeaders();
      await http.post(
        Uri.parse('$baseUrl/logout'),
        headers: headers,
      );
    } catch (e) {
      print("Error logging out from server: $e");
    } finally {
      await deleteToken();
      await _storage.deleteAll();
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear(); // Bersihkan juga SharedPreferences
    }
  }

  // --- USER & DASHBOARD ---
  // 3. User: Get Profile (/me)
  static Future<Map<String, dynamic>> getProfile() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/me'),
        headers: headers,
      );
      final data = jsonDecode(response.body);
      return {'status': response.statusCode, 'data': data};
    } catch (e) {
      return {'status': 500, 'data': null};
    }
  }

  // 4. Dashboard: Get Statistics
  static Future<Map<String, dynamic>> getStatistics() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/dashboard/statistics'),
        headers: headers,
      );
      final data = jsonDecode(response.body);
      return {'status': response.statusCode, 'data': data};
    } catch (e) {
      return {'status': 500, 'data': null};
    }
  }

  // --- TICKET SYSTEM ---
  // 5. Create Ticket
  static Future<Map<String, dynamic>> createTicket({
    required String title,
    required String description,
    required String priority,
  }) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/tickets'),
        headers: headers,
        body: jsonEncode({
          'title': title,
          'description': description,
          'priority': priority,
        }),
      );

      final data = jsonDecode(response.body);
      return {'status': response.statusCode, 'data': data};
    } catch (e) {
      return {
        'status': 500,
        'data': {'message': 'Gagal terhubung ke server: $e'}
      };
    }
  }

  // 6. Get List Tiket
  static Future<Map<String, dynamic>> getTickets({String? search, String? status}) async {
    try {
      final headers = await _getHeaders();
      
      final Map<String, String> queryParams = {};
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (status != null && status.isNotEmpty) queryParams['status'] = status;

      final uri = Uri.parse('$baseUrl/tickets').replace(queryParameters: queryParams.isNotEmpty ? queryParams : null);

      final response = await http.get(uri, headers: headers);

      final data = json.decode(response.body);
      return {
        'status': response.statusCode,
        'data': data['data'] ?? data,
      };
    } catch (e) {
      return {
        'status': 500,
        'message': e.toString(),
      };
    }
  }

  // 7. Get Detail Tiket beserta balasan chat
  static Future<Map<String, dynamic>> getTicketDetail(String code) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/tickets/$code'),
        headers: headers,
      );
      final data = jsonDecode(response.body);
      return {'status': response.statusCode, 'data': data};
    } catch (e) {
      return {'status': 500, 'message': e.toString()};
    }
  }

  // 8. Send Reply (Kirim Balasan Chat & Update Status)
  static Future<Map<String, dynamic>> sendReply(String code, String content, {String? status}) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/tickets/$code/reply'),
        headers: headers,
        body: jsonEncode({
          'content': content,
          if (status != null) 'status': status,
        }),
      );
      final data = jsonDecode(response.body);
      return {'status': response.statusCode, 'data': data};
    } catch (e) {
      return {'status': 500, 'message': e.toString()};
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
    final response = await http.post(
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
    );

    final data = jsonDecode(response.body);

    if (response.statusCode == 201) {
      // Simpan token & role jika otomatis auto-login setelah register
      String? token = data['data']?['token'];
      String? role = data['data']?['user']?['role'];

      if (token != null) await saveToken(token);
      if (role != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('role', role.toString());
      }
    }

    return {'status': response.statusCode, 'data': data};
  } catch (e) {
    return {
      'status': 500,
      'data': {'message': 'Gagal terhubung ke server: $e'}
    };
  }
 }
  // 1. Ambil daftar notifikasi
  static Future<Map<String, dynamic>> getNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    final response = await http.get(
      Uri.parse('$baseUrl/notifications'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    return {
      'status': response.statusCode,
      'data': jsonDecode(response.body),
    };
  }

  // 2. Tandai notifikasi sebagai 'read' (sudah dibaca)
  static Future<Map<String, dynamic>> markNotificationAsRead(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');

    final response = await http.post(
      Uri.parse('$baseUrl/notifications/$id/read'),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    return {
      'status': response.statusCode,
      'data': jsonDecode(response.body),
    };
  }
  
}