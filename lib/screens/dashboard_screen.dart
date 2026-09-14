import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'create_ticket_screen.dart';
import 'notification_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}



class _DashboardScreenState extends State<DashboardScreen> {
  int _unreadCount = 0;
  bool _isLoading = true;
  Map<String, dynamic>? _userProfile;
  Map<String, dynamic>? _statsData;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _loadUnreadNotifications();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);

    final profileRes = await ApiService.getProfile();
    final statsRes = await ApiService.getStatistics();

    if (mounted) {
      setState(() {
        if (profileRes['status'] == 200) _userProfile = profileRes['data'];
        if (statsRes['status'] == 200) _statsData = statsRes['data'];
        _isLoading = false;
      });
    }
  }

  Future<void> _loadUnreadNotifications() async {
  final res = await ApiService.getNotifications();
  if (mounted && res['status'] == 200 && res['data']['success'] == true) {
    final List notifications = res['data']['data'] ?? [];
    // Hitung berapa notifikasi yang 'read_at'-nya masih null
    final unreadList = notifications.where((item) => item['read_at'] == null).toList();
    setState(() {
      _unreadCount = unreadList.length;
    });
  }
}

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Logout'),
        content: const Text('Apakah Anda yakin ingin keluar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Keluar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ApiService.logout();
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Ambil Profil Data
    final profileData = _userProfile?['data'] ?? _userProfile;
    final userName = profileData?['name'] ?? 'User';

    // 2. Pembacaan Role secara ketat
    final String rawRole = (
      profileData?['role'] ?? 
      _statsData?['role'] ?? 
      _statsData?['data']?['role'] ?? 
      'user'
    ).toString().toLowerCase().trim();

    final bool isAdmin = rawRole == 'admin';

    // Helper Parsing Angka Aman
    int parseInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is double) return value.toInt();
      return int.tryParse(value.toString()) ?? 0;
    }

    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      return double.tryParse(value.toString()) ?? 0.0;
    }

    final rawData = _statsData?['data'] ?? _statsData;
    final Map<String, dynamic> dataMap = (rawData is Map<String, dynamic>) ? rawData : {};
    final distMap = (dataMap['status_distribution'] is Map<String, dynamic>)
        ? dataMap['status_distribution'] as Map<String, dynamic>
        : dataMap;

    final totalTickets = parseInt(dataMap['total_tickets'] ?? dataMap['total']);
    final avgResolutionTime = parseDouble(dataMap['avg_resolution_time']);
    final openCount = parseInt(distMap['open'] ?? dataMap['open']);
    final onProgressCount = parseInt(distMap['onprogress'] ?? distMap['in_progress'] ?? dataMap['onprogress']);
    final resolvedCount = parseInt(distMap['resolved'] ?? dataMap['resolved']);
    final rejectedCount = parseInt(distMap['rejected'] ?? dataMap['rejected']);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(
          isAdmin ? 'Dashboard Admin' : 'Dashboard User',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        actions: [
         // IKON NOTIFIKASI DENGAN BADGE MERAH
  Stack(
    alignment: Alignment.center,
    children: [
      IconButton(
        icon: const Icon(Icons.notifications_outlined),
        tooltip: 'Notifikasi',
        onPressed: () async {
          // Buka halaman notifikasi
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => NotificationScreen()),
          );
          // Setelah balik dari halaman notifikasi, refresh angka badge-nya
          _loadUnreadNotifications();
        },
      ),
      if (_unreadCount > 0)
        Positioned(
          right: 8,
          top: 8,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(10),
            ),
            constraints: const BoxConstraints(
              minWidth: 16,
              minHeight: 16,
            ),
            child: Text(
              _unreadCount > 99 ? '99+' : '$_unreadCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
    ],
  ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent),
            tooltip: 'Logout',
            onPressed: _handleLogout,
          ),
        ],
      ),
      // Perbaikan pada floatingActionButton menggunakan kondisi !isAdmin
      floatingActionButton: !isAdmin
          ? FloatingActionButton.extended(
              onPressed: () async {
                final isCreated = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CreateTicketScreen()),
                );
                if (isCreated == true) _loadDashboardData();
              },
              icon: const Icon(Icons.add_comment_rounded),
              label: const Text('Buat Tiket', style: TextStyle(fontWeight: FontWeight.bold)),
              backgroundColor: Theme.of(context).primaryColor,
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDashboardData,
              child: ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: Theme.of(context).primaryColor.withOpacity(0.15),
                            child: Icon(Icons.person, size: 30, color: Theme.of(context).primaryColor),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Selamat Datang, $userName!',
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isAdmin ? 'Ringkasan Aktivitas Sistem' : 'Layanan Bantuan & Tiket',
                                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  if (isAdmin) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.indigo.shade700, Colors.indigo.shade500],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.white.withOpacity(0.2),
                            radius: 24,
                            child: const Icon(Icons.timer_outlined, color: Colors.white, size: 28),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Rata-rata Penanganan', style: TextStyle(color: Colors.white70, fontSize: 13)),
                                const SizedBox(height: 2),
                                Text(
                                  '$avgResolutionTime Jam / Tiket',
                                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('Statistik Status Tiket', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.3,
                      children: [
                        _buildStatCard(title: 'Total Bulan Ini', count: '$totalTickets', icon: Icons.confirmation_number_outlined, color: Colors.blue),
                        _buildStatCard(title: 'Open', count: '$openCount', icon: Icons.error_outline, color: Colors.orange),
                        _buildStatCard(title: 'Onprogress', count: '$onProgressCount', icon: Icons.hourglass_top, color: Colors.amber[800]!),
                        _buildStatCard(title: 'Resolved', count: '$resolvedCount', icon: Icons.check_circle_outline, color: Colors.green),
                        _buildStatCard(title: 'Rejected', count: '$rejectedCount', icon: Icons.cancel_outlined, color: Colors.redAccent),
                      ],
                    ),
                  ] else ...[
                    Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          children: [
                            Icon(Icons.support_agent_rounded, size: 60, color: Theme.of(context).primaryColor),
                            const SizedBox(height: 12),
                            const Text(
                              'Ada Kendala Layanan?',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Silakan tekan tombol "Buat Tiket" di bawah untuk membuat laporan masalah baru.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[600], fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String count,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                Text(
                  count,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color),
                ),
              ],
            ),
            Text(
              title,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }
}