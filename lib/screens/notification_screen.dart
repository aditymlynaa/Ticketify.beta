import 'package:flutter/material.dart';
import '../services/api_service.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  bool _isLoading = true;
  List<dynamic> _notifications = [];

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    setState(() => _isLoading = true);
    final res = await ApiService.getNotifications();

    if (mounted) {
      if (res['status'] == 200 && res['data']['success'] == true) {
        setState(() {
          _notifications = res['data']['data'] ?? [];
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleMarkAsRead(String id, int index) async {
    final res = await ApiService.markNotificationAsRead(id);
    if (res['status'] == 200) {
      setState(() {
        // Update status read di list lokal secara instan
        _notifications[index]['read_at'] = DateTime.now().toIso8601String();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifikasi'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_off_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 12),
                      Text('Belum ada notifikasi', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchNotifications,
                  child: ListView.builder(
                    itemCount: _notifications.length,
                    itemBuilder: (context, index) {
                      final notif = _notifications[index];
                      final data = notif['data'] ?? {};
                      final bool isRead = notif['read_at'] != null;

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        color: isRead ? Colors.white : Colors.blue.shade50,
                        elevation: 1,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isRead ? Colors.grey[200] : Theme.of(context).primaryColor.withOpacity(0.2),
                            child: Icon(
                              Icons.notifications_active,
                              color: isRead ? Colors.grey : Theme.of(context).primaryColor,
                            ),
                          ),
                          title: Text(
                            data['title'] ?? 'Notifikasi Tiket',
                            style: TextStyle(
                              fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(data['message'] ?? 'Tidak ada detail pesan.'),
                              const SizedBox(height: 6),
                              Text(
                                notif['created_at'] != null
                                    ? notif['created_at'].toString().substring(0, 10)
                                    : '',
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                          onTap: () {
                            if (!isRead) {
                              _handleMarkAsRead(notif['id'], index);
                            }
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}