import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_formatter.dart';
import '../widgets/empty_state.dart';
import 'ticket_detail_screen.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  bool _isLoading = true;
  bool _isMarkingAll = false;
  String? _errorMessage;
  List<dynamic> _notifications = [];

  int get _unreadCount => _notifications
      .where((item) => item is Map && item['read_at'] == null)
      .length;

  bool get _hasUnread => _unreadCount > 0;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await ApiService.getNotifications();
    if (!mounted) return;

    if (res['status'] == 200) {
      final payload = res['data'];
      List<dynamic> notifications = [];

      if (payload is List) {
        notifications = payload;
      } else if (payload is Map && payload['data'] is List) {
        notifications = payload['data'] as List;
      }

      setState(() {
        _notifications = notifications;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = _messageFrom(
          res,
          'Gagal memuat notifikasi. Coba lagi.',
        );
      });
    }
  }

  /// Laravel menyimpan `data` sebagai array, tapi tetap amankan jika berupa
  /// string JSON (misalnya dari response lama).
  Map<String, dynamic> _notificationData(dynamic notification) {
    if (notification is! Map) return const {};

    final raw = notification['data'];
    if (raw is Map) return Map<String, dynamic>.from(raw);

    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        // Abaikan data yang tidak bisa di-parse.
      }
    }

    return const {};
  }

  Future<void> _handleMarkAsRead(dynamic notification, int index) async {
    if (notification is! Map || notification['read_at'] != null) return;

    final id = notification['id']?.toString();
    if (id == null) return;

    final res = await ApiService.markNotificationAsRead(id);
    if (!mounted) return;

    if (res['status'] == 200) {
      setState(() {
        if (_notifications[index] is Map) {
          _notifications[index]['read_at'] = DateTime.now().toIso8601String();
        }
      });
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_messageFrom(res, 'Gagal menandai notifikasi.')),
        ),
      );
    }
  }

  Future<void> _handleMarkAllAsRead() async {
    if (!_hasUnread || _isMarkingAll) return;

    setState(() => _isMarkingAll = true);
    final res = await ApiService.markAllNotificationsAsRead();
    if (!mounted) return;

    setState(() => _isMarkingAll = false);

    if (res['status'] == 200) {
      final now = DateTime.now().toIso8601String();
      setState(() {
        for (final notification in _notifications) {
          if (notification is Map && notification['read_at'] == null) {
            notification['read_at'] = now;
          }
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Semua notifikasi ditandai sudah dibaca.'),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_messageFrom(res, 'Gagal menandai semua notifikasi.')),
        ),
      );
    }
  }

  Future<void> _openNotification(dynamic notification, int index) async {
    final data = _notificationData(notification);
    final code = data['ticket_code']?.toString();

    await _handleMarkAsRead(notification, index);

    if (!mounted || code == null || code.isEmpty) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TicketDetailScreen(ticketCode: code),
      ),
    );

    if (mounted) _fetchNotifications();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifikasi'),
        actions: [
          if (_hasUnread)
            IconButton(
              tooltip: 'Tandai semua dibaca',
              onPressed: _isMarkingAll ? null : _handleMarkAllAsRead,
              icon: _isMarkingAll
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.done_all_rounded),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Tidak bisa memuat notifikasi',
          message: _errorMessage!,
          actionLabel: 'Coba lagi',
          onAction: _fetchNotifications,
        ),
      );
    }

    if (_notifications.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchNotifications,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: const Center(
                  child: EmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: 'Belum ada notifikasi',
                    message:
                        'Kabar terbaru tentang tiketmu akan muncul di sini.',
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchNotifications,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (_hasUnread)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: AppColors.blue,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    '$_unreadCount belum dibaca',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          for (var index = 0; index < _notifications.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _NotificationCard(
                notification: _notifications[index],
                data: _notificationData(_notifications[index]),
                onTap: () => _openNotification(_notifications[index], index),
              ),
            ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final dynamic notification;
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _NotificationCard({
    required this.notification,
    required this.data,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isRead = notification is Map && notification['read_at'] != null;
    final title = (data['title'] ?? 'Notifikasi tiket').toString();
    final message = (data['message'] ?? 'Tidak ada detail pesan.').toString();
    final ticketCode = data['ticket_code']?.toString() ?? '';
    final createdAt = notification is Map
        ? (notification['created_at'] ?? '').toString()
        : '';

    return Material(
      color: isRead ? AppColors.white : AppColors.blueSoft,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        hoverColor: AppColors.blueSoft.withValues(alpha: 0.6),
        splashColor: AppColors.blueSoft,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isRead
                  ? AppColors.line
                  : AppColors.blue.withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isRead ? AppColors.slateSoft : AppColors.white,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  isRead
                      ? Icons.notifications_none_rounded
                      : Icons.notifications_active_rounded,
                  size: 18,
                  color: isRead ? AppColors.muted : AppColors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 13.5,
                              height: 1.35,
                              fontWeight: isRead
                                  ? FontWeight.w600
                                  : FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        if (!isRead) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 7,
                            height: 7,
                            margin: const EdgeInsets.only(top: 5),
                            decoration: const BoxDecoration(
                              color: AppColors.blue,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (ticketCode.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.slateSoft,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '#$ticketCode',
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: AppColors.blueDark,
                              ),
                            ),
                          ),
                        const Spacer(),
                        Text(
                          formatDateTime(createdAt),
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String formatBadgeCount(int count) {
  if (count > 9) return '9+';
  return count.toString();
}

String _messageFrom(Map<String, dynamic> response, String fallback) {
  final data = response['data'];
  if (data is Map) {
    final message = data['message'];
    if (message != null && message.toString().trim().isNotEmpty) {
      return message.toString();
    }
  }
  return fallback;
}
