import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_logo.dart';
import '../widgets/empty_state.dart';
import '../widgets/inline_alert.dart';
import '../widgets/status_badge.dart';
import '../utils/date_formatter.dart';
import 'create_ticket_screen.dart';
import 'notification_screen.dart';
import 'ticket_detail_screen.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback? onOpenTickets;

  const DashboardScreen({super.key, this.onOpenTickets});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  bool _isLoading = true;
  String? _errorMessage;
  int _unreadCount = 0;

  Timer? _pollTimer;

  Map<String, dynamic>? _userProfile;
  Map<String, dynamic>? _statsData;
  List<dynamic> _myTickets = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _loadUnreadNotifications(),
    );
    _loadDashboardData();
    _loadUnreadNotifications();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadUnreadNotifications();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final results = await Future.wait([
      ApiService.getProfile(),
      ApiService.getStatistics(),
    ]);

    if (!mounted) return;

    final profileRes = results[0];
    final statsRes = results[1];

    final profile = profileRes['status'] == 200
        ? _asMap(profileRes['data'])
        : null;
    final stats = statsRes['status'] == 200 ? _asMap(statsRes['data']) : null;

    final profileData = _asMap(profile?['data']) ?? profile;
    final statsData = _asMap(stats?['data']) ?? stats;

    final role = (profileData?['role'] ?? statsData?['role'] ?? 'user')
        .toString()
        .toLowerCase()
        .trim();

    List<dynamic> tickets = [];
    String? error;

    if (profileRes['status'] != 200) {
      error = _messageFrom(profileRes, 'Gagal memuat profil pengguna.');
    } else if (role == 'admin' && statsRes['status'] != 200) {
      error = _messageFrom(statsRes, 'Gagal memuat statistik tiket.');
    } else if (role != 'admin') {
      // Statistik user sekarang dihitung backend; di sini cukup ambil
      // beberapa tiket terbaru untuk kartu "Tiket terbaru".
      final recentRes = await ApiService.getTickets(perPage: 3);
      if (!mounted) return;

      if (recentRes['status'] == 200) {
        tickets = _extractTickets(recentRes);
      } else {
        error = _messageFrom(recentRes, 'Gagal memuat tiket terbaru.');
      }
    }

    setState(() {
      _userProfile = profile;
      _statsData = stats;
      _myTickets = tickets;
      _errorMessage = error;
      _isLoading = false;
    });
  }

  Future<void> _loadUnreadNotifications() async {
    final res = await ApiService.getUnreadCount();
    if (!mounted || res['status'] != 200) return;

    final payload = res['data'];
    final data = payload is Map ? (payload['data'] ?? payload) : null;
    final rawCount = data is Map ? data['unread_count'] : data;
    final count = int.tryParse(rawCount?.toString() ?? '') ?? 0;

    setState(() => _unreadCount = count);
  }

  Future<void> _openNotifications() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const NotificationScreen()),
    );
    if (mounted) _loadUnreadNotifications();
  }

  Future<void> _openCreateTicket() async {
    final created = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreateTicketScreen()),
    );

    if (created == true && mounted) {
      _loadDashboardData();
      _loadUnreadNotifications();
    }
  }

  Future<void> _openTicket(String code) async {
    if (code.isEmpty) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TicketDetailScreen(ticketCode: code),
      ),
    );

    if (mounted) _loadDashboardData();
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keluar dari akun?'),
        content: const Text(
          'Kamu perlu login kembali untuk membuka tiket dan notifikasi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.red),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await ApiService.logout();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = _userProfile;
    final profileData = _asMap(profile?['data']) ?? profile;
    final stats = _statsData;
    final statsData = _asMap(stats?['data']) ?? stats;

    final userName = (profileData?['name'] ?? 'Pengguna').toString();
    final role = (profileData?['role'] ?? statsData?['role'] ?? 'user')
        .toString()
        .toLowerCase()
        .trim();
    final isAdmin = role == 'admin';

    final distribution =
        _asMap(statsData?['status_distribution']) ?? statsData ?? const {};
    final totalTickets = _asInt(
      statsData?['total_tickets'] ?? statsData?['total'],
    );
    final avgResolution = _asDouble(statsData?['avg_resolution_time']);
    final openCount = _asInt(distribution['open']);
    final onProgressCount = _asInt(
      distribution['onprogress'] ?? distribution['in_progress'],
    );
    final resolvedCount = _asInt(distribution['resolved']);
    final rejectedCount = _asInt(distribution['rejected']);
    final overdueCount = _asInt(statsData?['overdue_tickets']);
    final unassignedCount = _asInt(statsData?['unassigned_tickets']);
    final assignedToMe = _asInt(statsData?['assigned_to_me']);

    var localOpen = 0;
    var localResolved = 0;
    for (final item in _myTickets) {
      if (item is! Map) continue;
      final status = (item['status'] ?? '').toString().toLowerCase();
      if (status == 'resolved') {
        localResolved++;
      } else if (status != 'rejected') {
        localOpen++;
      }
    }

    // Statistik dari backend (akurat untuk seluruh tiket user). Fallback ke
    // hitungan lokal kalau backend lama belum mengirim field ini.
    final hasUserStats = statsData?['total_tickets'] != null;
    final myTotal = hasUserStats
        ? _asInt(statsData?['total_tickets'])
        : _myTickets.length;
    final myOpen = hasUserStats
        ? _asInt(statsData?['active_tickets'])
        : localOpen;
    final myResolved = hasUserStats
        ? _asInt(statsData?['resolved_tickets'])
        : localResolved;

    final showFullLoader = _isLoading && profile == null;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const AppBrand(logoSize: 30, showTagline: false),
        actions: [
          _NotificationButton(
            count: _unreadCount,
            onPressed: _openNotifications,
          ),
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            tooltip: 'Akun',
            offset: const Offset(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AppColors.line),
            ),
            color: AppColors.white,
            onSelected: (value) {
              if (value == 'logout') _handleLogout();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, size: 18, color: AppColors.red),
                    SizedBox(width: 10),
                    Text(
                      'Keluar',
                      style: TextStyle(fontSize: 14, color: AppColors.red),
                    ),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _Avatar(name: userName),
            ),
          ),
        ],
      ),
      body: showFullLoader
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _loadDashboardData();
                await _loadUnreadNotifications();
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _buildGreeting(userName, isAdmin),
                  const SizedBox(height: 20),

                  if (_errorMessage != null) ...[
                    InlineAlert(message: _errorMessage!),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _loadDashboardData,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Coba lagi'),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (isAdmin)
                    ..._buildAdminContent(
                      totalTickets: totalTickets,
                      avgResolution: avgResolution,
                      openCount: openCount,
                      onProgressCount: onProgressCount,
                      resolvedCount: resolvedCount,
                      rejectedCount: rejectedCount,
                      overdueCount: overdueCount,
                      unassignedCount: unassignedCount,
                      assignedToMe: assignedToMe,
                    )
                  else
                    ..._buildUserContent(
                      total: myTotal,
                      active: myOpen,
                      resolved: myResolved,
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildGreeting(String userName, bool isAdmin) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_greeting()},',
          style: const TextStyle(fontSize: 13, color: AppColors.muted),
        ),
        const SizedBox(height: 2),
        Text(
          userName,
          style: const TextStyle(
            fontSize: 26,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.7,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isAdmin
              ? 'Berikut ringkasan aktivitas tim support hari ini.'
              : 'Pantau laporanmu dan lihat kabar terbaru dari tim support.',
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.5,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildUserContent({
    required int total,
    required int active,
    required int resolved,
  }) {
    final recent = _myTickets.take(3).toList();

    return [
      _UserHeroCard(onCreate: _openCreateTicket),
      const SizedBox(height: 20),
      _MyTicketsSummary(total: total, active: active, resolved: resolved),
      const SizedBox(height: 24),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Tiket terbaru',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: AppColors.ink,
              ),
            ),
          ),
          if (recent.isNotEmpty)
            TextButton(
              onPressed: widget.onOpenTickets,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
              ),
              child: const Text('Lihat semua'),
            ),
        ],
      ),
      const SizedBox(height: 10),
      if (recent.isEmpty)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: EmptyState(
            icon: Icons.inbox_outlined,
            title: 'Belum ada tiket',
            message:
                'Tiket yang kamu buat akan muncul di sini beserta statusnya.',
          ),
        )
      else
        ...recent.map((item) {
          final ticket = item is Map
              ? Map<String, dynamic>.from(item)
              : <String, dynamic>{};
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _RecentTicketCard(
              ticket: ticket,
              onTap: () => _openTicket(
                (ticket['code'] ?? ticket['kode'] ?? '').toString(),
              ),
            ),
          );
        }),
    ];
  }

  List<Widget> _buildAdminContent({
    required int totalTickets,
    required double avgResolution,
    required int openCount,
    required int onProgressCount,
    required int resolvedCount,
    required int rejectedCount,
    required int overdueCount,
    required int unassignedCount,
    required int assignedToMe,
  }) {
    return [
      _AdminOverviewCard(
        total: totalTickets,
        avgResolution: avgResolution,
        openCount: openCount,
        onProgressCount: onProgressCount,
        resolvedCount: resolvedCount,
        rejectedCount: rejectedCount,
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          Expanded(
            child: _MiniStat(
              label: 'Lewat SLA',
              value: overdueCount,
              icon: Icons.timer_off_outlined,
              color: AppColors.red,
              background: AppColors.redSoft,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _MiniStat(
              label: 'Belum ditugaskan',
              value: unassignedCount,
              icon: Icons.person_search_outlined,
              color: AppColors.amber,
              background: AppColors.amberSoft,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _MiniStat(
              label: 'Tugas saya',
              value: assignedToMe,
              icon: Icons.assignment_ind_outlined,
              color: AppColors.blue,
              background: AppColors.blueSoft,
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      const Text(
        'Status tiket',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: AppColors.ink,
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _StatCard(
              label: 'Open',
              value: openCount,
              icon: Icons.bolt_rounded,
              color: AppColors.amber,
              background: AppColors.amberSoft,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              label: 'Diproses',
              value: onProgressCount,
              icon: Icons.autorenew_rounded,
              color: AppColors.blue,
              background: AppColors.blueSoft,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _StatCard(
              label: 'Selesai',
              value: resolvedCount,
              icon: Icons.check_circle_outline_rounded,
              color: AppColors.greenDark,
              background: AppColors.greenSoft,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              label: 'Ditolak',
              value: rejectedCount,
              icon: Icons.block_rounded,
              color: AppColors.red,
              background: AppColors.redSoft,
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: widget.onOpenTickets,
        icon: const Icon(Icons.arrow_forward_rounded, size: 18),
        label: const Text('Kelola semua tiket'),
      ),
    ];
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final Color background;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 19,
              height: 1,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: color,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 2,
            style: const TextStyle(
              fontSize: 10,
              height: 1.3,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  final int count;
  final VoidCallback onPressed;

  const _NotificationButton({required this.count, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Notifikasi',
      onPressed: onPressed,
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_none_rounded),
          if (count > 0)
            Positioned(
              right: -5,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 1.5,
                ),
                constraints: const BoxConstraints(minWidth: 16),
                decoration: BoxDecoration(
                  color: AppColors.blue,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.white, width: 1.5),
                ),
                child: Text(
                  formatBadgeCount(count),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String name;

  const _Avatar({required this.name});

  static String initialsOf(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) return 'U';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();

    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.blueSoft,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Text(
        initialsOf(name),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.blueDark,
        ),
      ),
    );
  }
}

class _UserHeroCard extends StatelessWidget {
  final VoidCallback onCreate;

  const _UserHeroCard({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.blue,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.support_agent_rounded,
              color: Colors.white,
              size: 23,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Ada kendala layanan?',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Buat tiket baru dan tim support akan menindaklanjuti laporanmu.',
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: onCreate,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppColors.blueDark,
              minimumSize: const Size.fromHeight(46),
            ),
            icon: const Icon(Icons.add_rounded, size: 19),
            label: const Text('Buat tiket baru'),
          ),
        ],
      ),
    );
  }
}

class _MyTicketsSummary extends StatelessWidget {
  final int total;
  final int active;
  final int resolved;

  const _MyTicketsSummary({
    required this.total,
    required this.active,
    required this.resolved,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _SummaryItem(label: 'Total', value: total),
            const VerticalDivider(width: 1, color: AppColors.line),
            _SummaryItem(label: 'Diproses', value: active),
            const VerticalDivider(width: 1, color: AppColors.line),
            _SummaryItem(
              label: 'Selesai',
              value: resolved,
              valueColor: AppColors.greenDark,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final int value;
  final Color valueColor;

  const _SummaryItem({
    required this.label,
    required this.value,
    this.valueColor = AppColors.ink,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.6,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _AdminOverviewCard extends StatelessWidget {
  final int total;
  final double avgResolution;
  final int openCount;
  final int onProgressCount;
  final int resolvedCount;
  final int rejectedCount;

  const _AdminOverviewCard({
    required this.total,
    required this.avgResolution,
    required this.openCount,
    required this.onProgressCount,
    required this.resolvedCount,
    required this.rejectedCount,
  });

  @override
  Widget build(BuildContext context) {
    final distributionTotal =
        openCount + onProgressCount + resolvedCount + rejectedCount;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TOTAL TIKET',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.1,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$total',
                      style: const TextStyle(
                        fontSize: 38,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.4,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.blueSoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.insights_rounded,
                  size: 21,
                  color: AppColors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _DistributionBar(
            open: openCount,
            onProgress: onProgressCount,
            resolved: resolvedCount,
            rejected: rejectedCount,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _LegendItem(
                color: AppColors.amber,
                label: 'Open',
                value: openCount,
              ),
              _LegendItem(
                color: AppColors.blue,
                label: 'Diproses',
                value: onProgressCount,
              ),
              _LegendItem(
                color: AppColors.green,
                label: 'Selesai',
                value: resolvedCount,
              ),
              _LegendItem(
                color: AppColors.red,
                label: 'Ditolak',
                value: rejectedCount,
              ),
            ],
          ),
          if (distributionTotal == 0) ...[
            const SizedBox(height: 6),
            const Text(
              'Belum ada tiket untuk ditampilkan.',
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1),
          ),
          Row(
            children: [
              const Icon(
                Icons.timer_outlined,
                size: 18,
                color: AppColors.muted,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Rata-rata penanganan',
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                ),
              ),
              Text(
                '${_formatHours(avgResolution)} jam',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DistributionBar extends StatelessWidget {
  final int open;
  final int onProgress;
  final int resolved;
  final int rejected;

  const _DistributionBar({
    required this.open,
    required this.onProgress,
    required this.resolved,
    required this.rejected,
  });

  @override
  Widget build(BuildContext context) {
    final total = open + onProgress + resolved + rejected;

    if (total == 0) {
      return Container(
        height: 10,
        decoration: BoxDecoration(
          color: AppColors.slateSoft,
          borderRadius: BorderRadius.circular(999),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            if (open > 0)
              Expanded(
                flex: open,
                child: Container(color: AppColors.amber),
              ),
            if (onProgress > 0)
              Expanded(
                flex: onProgress,
                child: Container(color: AppColors.blue),
              ),
            if (resolved > 0)
              Expanded(
                flex: resolved,
                child: Container(color: AppColors.green),
              ),
            if (rejected > 0)
              Expanded(
                flex: rejected,
                child: Container(color: AppColors.red),
              ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final int value;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label ',
          style: const TextStyle(fontSize: 11.5, color: AppColors.muted),
        ),
        Text(
          '$value',
          style: const TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final Color background;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: color),
              ),
              const Spacer(),
              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 22,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentTicketCard extends StatelessWidget {
  final Map<String, dynamic> ticket;
  final VoidCallback onTap;

  const _RecentTicketCard({required this.ticket, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final title = (ticket['title'] ?? 'Tanpa judul').toString();
    final code = (ticket['code'] ?? ticket['kode'] ?? '').toString();
    final status = (ticket['status'] ?? 'open').toString();
    final createdAt = (ticket['created_at'] ?? '').toString();

    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        hoverColor: AppColors.blueSoft.withValues(alpha: 0.6),
        splashColor: AppColors.blueSoft,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  StatusBadge(status: status, compact: true),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    '#$code',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.blueDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 3,
                    height: 3,
                    decoration: const BoxDecoration(
                      color: AppColors.line,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      formatDateTime(createdAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.muted,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.muted,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Helper parsing ---

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

int _asInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

double _asDouble(dynamic value) {
  if (value == null) return 0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
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

List<dynamic> _extractTickets(Map<String, dynamic> response) {
  final data = response['data'];

  if (data is List) return data;
  if (data is Map) {
    if (data['data'] is List) return data['data'] as List;
    if (data['tickets'] is List) return data['tickets'] as List;
    final nested = data['data'];
    if (nested is Map && nested['data'] is List) return nested['data'] as List;
  }
  return const [];
}

String _formatHours(double value) {
  if (value == 0) return '0';
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 11) return 'Selamat pagi';
  if (hour < 15) return 'Selamat siang';
  if (hour < 18) return 'Selamat sore';
  return 'Selamat malam';
}
