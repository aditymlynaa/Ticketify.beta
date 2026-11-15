import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/date_formatter.dart';
import '../widgets/empty_state.dart';
import '../widgets/sla_badge.dart';
import '../widgets/status_badge.dart';
import 'create_ticket_screen.dart';
import 'ticket_detail_screen.dart';

class TicketListScreen extends StatefulWidget {
  const TicketListScreen({super.key});

  @override
  State<TicketListScreen> createState() => TicketListScreenState();
}

class TicketListScreenState extends State<TicketListScreen>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;
  Timer? _pollTimer;

  List<dynamic> _tickets = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _loadMoreFailed = false;
  String? _errorMessage;
  String _searchQuery = '';
  String? _selectedStatus;
  String? _selectedCategory;
  String? _selectedAssigned;
  List<({String value, String label})> _categories = const [];
  List<dynamic> _admins = const [];
  String? _userRole;
  int _requestId = 0;

  int _page = 1;
  int _lastPage = 1;
  int _totalCount = 0;

  static const _pageSize = 15;

  static const _statusFilters = <({String? value, String label})>[
    (value: null, label: 'Semua'),
    (value: 'open', label: 'Open'),
    (value: 'onprogress', label: 'Diproses'),
    (value: 'resolved', label: 'Selesai'),
    (value: 'rejected', label: 'Ditolak'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    _pollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _pollUpdates(),
    );
    _loadUserRole();
    reload();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _pollUpdates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _debounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _userRole = prefs.getString('role'));
  }

  /// Dipanggil dari MainScreen saat tab Tiket dibuka.
  Future<void> reload() => _fetchTickets();

  bool get _hasMore => _page < _lastPage;

  Future<void> _fetchTickets({bool reset = true, bool silent = false}) async {
    if (!reset && (_isLoadingMore || !_hasMore)) return;

    final requestId = ++_requestId;
    final targetPage = reset ? 1 : _page + 1;

    setState(() {
      if (reset) {
        if (!silent) _isLoading = true;
        _isLoadingMore = false;
        _loadMoreFailed = false;
        if (!silent) _errorMessage = null;
      } else {
        _isLoadingMore = true;
        _loadMoreFailed = false;
      }
    });

    final response = await ApiService.getTickets(
      search: _searchQuery.isNotEmpty ? _searchQuery : null,
      status: _selectedStatus,
      category: _selectedCategory,
      assigned: _selectedAssigned,
      page: targetPage,
      perPage: _pageSize,
    );

    if (!mounted || requestId != _requestId) return;

    if (response['status'] != 200) {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;

        if (!reset) {
          _loadMoreFailed = true;
        } else if (!silent) {
          _errorMessage = _messageFrom(
            response,
            'Gagal memuat daftar tiket. Periksa koneksi lalu coba lagi.',
          );
        }
      });
      return;
    }

    final incoming = _extractTickets(response);
    final meta = _asMap(response['meta']);

    setState(() {
      if (reset) {
        _tickets = incoming;
      } else {
        _appendUnique(incoming);
      }

      _page = _asInt(meta['current_page']) > 0
          ? _asInt(meta['current_page'])
          : targetPage;
      _lastPage = _asInt(meta['last_page']) > 0
          ? _asInt(meta['last_page'])
          : _page;
      _totalCount = _asInt(meta['total']) > 0
          ? _asInt(meta['total'])
          : _tickets.length;

      _isLoading = false;
      _isLoadingMore = false;
      _errorMessage = null;
    });
  }

  void _appendUnique(List<dynamic> incoming) {
    final known = _tickets.map(_ticketKey).toSet();

    for (final item in incoming) {
      if (known.add(_ticketKey(item))) _tickets.add(item);
    }
  }

  String _ticketKey(dynamic item) {
    if (item is Map) {
      return (item['code'] ?? item['id'] ?? item).toString();
    }
    return item.toString();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 240) {
      _fetchTickets(reset: false);
    }
  }

  void _pollUpdates() {
    if (!mounted || _isLoading || _isLoadingMore) return;

    // Hanya segarkan halaman pertama supaya posisi scroll tidak meloncat.
    if (_page > 1) return;

    _fetchTickets(silent: true);
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value.trim());
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _fetchTickets);
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() => _searchQuery = '');
    _fetchTickets();
  }

  void _selectStatus(String? status) {
    if (_selectedStatus == status) return;
    setState(() => _selectedStatus = status);
    _fetchTickets();
  }

  void _resetFilters() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _selectedStatus = null;
      _selectedCategory = null;
      _selectedAssigned = null;
    });
    _fetchTickets();
  }

  Future<void> _ensureMeta() async {
    if (_categories.isNotEmpty) return;

    final res = await ApiService.getTicketMeta();
    if (!mounted || res['status'] != 200) return;

    final payload = res['data'];
    final data = payload is Map ? payload['data'] : null;
    final rawCategories = data is Map ? data['categories'] : null;
    final rawAdmins = data is Map ? data['admins'] : null;

    if (rawCategories is List && rawCategories.isNotEmpty) {
      final loaded = rawCategories
          .whereType<Map>()
          .map(
            (item) => (
              value: (item['value'] ?? '').toString(),
              label: (item['label'] ?? '').toString(),
            ),
          )
          .where((item) => item.value.isNotEmpty)
          .toList();

      if (mounted) {
        setState(() {
          _categories = loaded;
          if (rawAdmins is List) _admins = rawAdmins;
        });
      }
    }
  }

  Future<void> _openFilterSheet() async {
    await _ensureMeta();
    if (!mounted) return;

    var category = _selectedCategory;
    var assigned = _selectedAssigned;

    final result =
        await showModalBottomSheet<({String? category, String? assigned})>(
          context: context,
          backgroundColor: AppColors.white,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          builder: (context) => StatefulBuilder(
            builder: (context, setSheetState) {
              return SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.line,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Filter tiket',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Kategori',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Semua'),
                            selected: category == null,
                            showCheckmark: false,
                            onSelected: (_) =>
                                setSheetState(() => category = null),
                          ),
                          for (final item in _categories)
                            ChoiceChip(
                              label: Text(item.label),
                              selected: category == item.value,
                              showCheckmark: false,
                              onSelected: (_) =>
                                  setSheetState(() => category = item.value),
                            ),
                        ],
                      ),
                      if (_admins.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        const Text(
                          'Penugasan',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Semua'),
                              selected: assigned == null,
                              showCheckmark: false,
                              onSelected: (_) =>
                                  setSheetState(() => assigned = null),
                            ),
                            ChoiceChip(
                              label: const Text('Ditugaskan ke saya'),
                              selected: assigned == 'me',
                              showCheckmark: false,
                              onSelected: (_) =>
                                  setSheetState(() => assigned = 'me'),
                            ),
                            ChoiceChip(
                              label: const Text('Belum ditugaskan'),
                              selected: assigned == 'unassigned',
                              showCheckmark: false,
                              onSelected: (_) =>
                                  setSheetState(() => assigned = 'unassigned'),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context, (
                                category: null,
                                assigned: null,
                              )),
                              child: const Text('Reset'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => Navigator.pop(context, (
                                category: category,
                                assigned: assigned,
                              )),
                              child: const Text('Terapkan'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );

    if (result == null || !mounted) return;

    setState(() {
      _selectedCategory = result.category;
      _selectedAssigned = result.assigned;
    });
    _fetchTickets();
  }

  Future<void> _openTicket(String code) async {
    if (code.isEmpty) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TicketDetailScreen(ticketCode: code),
      ),
    );

    if (mounted) _fetchTickets();
  }

  Future<void> _openCreateTicket() async {
    final created = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreateTicketScreen()),
    );

    if (created == true && mounted) _fetchTickets();
  }

  @override
  Widget build(BuildContext context) {
    final hasFilter =
        _searchQuery.isNotEmpty ||
        _selectedStatus != null ||
        _selectedCategory != null ||
        _selectedAssigned != null;
    final hasExtraFilter =
        _selectedCategory != null || _selectedAssigned != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tiket'),
        actions: [
          IconButton(
            tooltip: 'Filter',
            onPressed: _openFilterSheet,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.tune_rounded),
                if (hasExtraFilter)
                  Positioned(
                    right: -1,
                    top: -1,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: AppColors.blue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _fetchTickets,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: _userRole == 'admin'
          ? null
          : FloatingActionButton.extended(
              onPressed: _openCreateTicket,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Buat tiket'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: _onSearchChanged,
              onSubmitted: (_) {
                _debounce?.cancel();
                _fetchTickets();
              },
              decoration: InputDecoration(
                hintText: 'Cari judul atau kode tiket',
                filled: true,
                fillColor: AppColors.white,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Hapus pencarian',
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _statusFilters.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = _statusFilters[index];
                final selected = _selectedStatus == filter.value;

                return ChoiceChip(
                  selected: selected,
                  showCheckmark: false,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  label: Text(filter.label),
                  labelStyle: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected ? AppColors.blueDark : AppColors.muted,
                  ),
                  onSelected: (_) => _selectStatus(filter.value),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            child: Row(
              children: [
                Text(
                  _isLoading && _tickets.isEmpty
                      ? 'Memuat tiket...'
                      : _totalCount > _tickets.length
                      ? '${_tickets.length} dari $_totalCount tiket'
                      : '$_totalCount tiket',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.muted,
                  ),
                ),
                const Spacer(),
                if (_isLoading && _tickets.isNotEmpty)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          Expanded(child: _buildBody(hasFilter: hasFilter)),
        ],
      ),
    );
  }

  Widget _buildBody({required bool hasFilter}) {
    if (_isLoading && _tickets.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return _scrollable(
        EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Tidak bisa memuat tiket',
          message: _errorMessage!,
          actionLabel: 'Coba lagi',
          onAction: _fetchTickets,
        ),
      );
    }

    if (_tickets.isEmpty) {
      return _scrollable(
        EmptyState(
          icon: hasFilter
              ? Icons.search_off_rounded
              : Icons.confirmation_number_outlined,
          title: hasFilter ? 'Tidak ada hasil' : 'Belum ada tiket',
          message: hasFilter
              ? 'Coba ubah kata kunci atau pilih filter status lain.'
              : 'Tiket yang dibuat akan muncul di sini lengkap dengan status dan prioritasnya.',
          actionLabel: hasFilter
              ? 'Reset filter'
              : (_userRole == 'admin' ? null : 'Buat tiket'),
          onAction: hasFilter ? _resetFilters : _openCreateTicket,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchTickets,
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _tickets.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          if (index == _tickets.length) {
            return _LoadMoreFooter(
              failed: _loadMoreFailed,
              onRetry: () => _fetchTickets(reset: false),
            );
          }

          final raw = _tickets[index];
          if (raw is! Map) return const SizedBox.shrink();

          final ticket = Map<String, dynamic>.from(raw);
          return _TicketCard(
            ticket: ticket,
            onTap: () => _openTicket(
              (ticket['code'] ?? ticket['kode'] ?? '').toString(),
            ),
          );
        },
      ),
    );
  }

  Widget _scrollable(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  final bool failed;
  final VoidCallback onRetry;

  const _LoadMoreFooter({required this.failed, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: failed
            ? TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('Gagal memuat. Coba lagi'),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'Memuat tiket lainnya...',
                    style: TextStyle(fontSize: 12, color: AppColors.muted),
                  ),
                ],
              ),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  final Map<String, dynamic> ticket;
  final VoidCallback onTap;

  const _TicketCard({required this.ticket, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final title = (ticket['title'] ?? ticket['judul'] ?? 'Tanpa judul')
        .toString();
    final code = (ticket['code'] ?? ticket['kode'] ?? '').toString();
    final status = (ticket['status'] ?? 'open').toString();
    final priority = (ticket['priority'] ?? '').toString();
    final createdAt = (ticket['created_at'] ?? ticket['tanggal'] ?? '')
        .toString();
    final categoryLabel = (ticket['category_label'] ?? '').toString();
    final dueAt = ticket['due_at']?.toString();
    final slaStatus = ticket['sla_status']?.toString();

    final unread =
        int.tryParse(
          (ticket['unread_replies_count'] ?? ticket['unread_count'] ?? 0)
              .toString(),
        ) ??
        0;

    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        hoverColor: AppColors.blueSoft.withValues(alpha: 0.6),
        splashColor: AppColors.blueSoft,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
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
                        letterSpacing: -0.1,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: StatusBadge(status: status, compact: true),
                  ),
                ],
              ),
              const SizedBox(height: 8),
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
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        PriorityBadge(priority: priority),
                        if (categoryLabel.isNotEmpty)
                          Text(
                            categoryLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.muted,
                            ),
                          ),
                        SlaBadge(
                          dueAt: dueAt,
                          slaStatus: slaStatus,
                          compact: true,
                        ),
                        if (unread > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.greenSoft,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.chat_bubble_rounded,
                                  size: 11,
                                  color: AppColors.greenDark,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  '$unread pesan baru',
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.greenDark,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
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

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

int _asInt(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
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
  final resData = response['data'];

  if (resData is List) return resData;
  if (resData is Map) {
    if (resData['data'] is List) return resData['data'] as List;
    if (resData['tickets'] is List) return resData['tickets'] as List;
    final nested = _asMap(resData['data']);
    if (nested['data'] is List) return nested['data'] as List;
  }

  return const [];
}
