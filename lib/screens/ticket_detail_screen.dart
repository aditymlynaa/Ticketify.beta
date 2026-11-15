import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/attachment_picker.dart';
import '../utils/date_formatter.dart';
import '../widgets/attachment_list.dart';
import '../widgets/empty_state.dart';
import '../widgets/sla_badge.dart';
import '../widgets/status_badge.dart';

class TicketDetailScreen extends StatefulWidget {
  final String ticketCode;

  const TicketDetailScreen({super.key, required this.ticketCode});

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  final TextEditingController _replyController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isSending = false;
  bool _isRefreshing = false;
  bool _isUpdatingStatus = false;
  bool _isUploading = false;
  bool _isInternalNote = false;
  String? _errorMessage;
  List<PickedAttachment> _pendingAttachments = [];
  List<dynamic> _admins = [];

  Timer? _pollTimer;

  Map<String, dynamic>? _ticket;
  List<dynamic> _replies = [];

  String _userRole = 'user';
  String? _currentUserId;
  String? _currentUserName;
  String _selectedStatus = 'onprogress';

  static const _statuses = <({String value, String label})>[
    (value: 'open', label: 'Open'),
    (value: 'onprogress', label: 'Diproses'),
    (value: 'resolved', label: 'Selesai'),
    (value: 'rejected', label: 'Ditolak'),
  ];

  @override
  void initState() {
    super.initState();
    _loadIdentity();
    _loadMeta();
    _loadDetail();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _pollForUpdates(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _replyController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return (position.maxScrollExtent - position.pixels) < 140;
  }

  void _pollForUpdates() {
    if (!mounted || _isLoading || _isSending || _isUpdatingStatus) return;

    _loadDetail(scrollToBottom: _isNearBottom, silent: true);
  }

  Future<void> _loadIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _userRole = prefs.getString('role') ?? 'user';
      _currentUserId = prefs.getString('user_id');
      _currentUserName = prefs.getString('user_name');
    });
  }

  Future<void> _loadMeta() async {
    final res = await ApiService.getTicketMeta();
    if (!mounted || res['status'] != 200) return;

    final payload = res['data'];
    final data = payload is Map ? payload['data'] : null;
    final admins = data is Map ? data['admins'] : null;

    if (admins is List) {
      setState(() => _admins = admins);
    }
  }

  Future<void> _loadDetail({
    bool scrollToBottom = true,
    bool silent = false,
  }) async {
    if (_isRefreshing) return;
    _isRefreshing = true;

    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    final res = await ApiService.getTicketDetail(widget.ticketCode);
    _isRefreshing = false;

    if (!mounted) return;

    if (res['status'] == 200) {
      final payload = res['data'];
      final data = _asMap(
        payload is Map && payload['data'] is Map ? payload['data'] : payload,
      );
      final replies = data['replies'] is List
          ? data['replies'] as List
          : const [];

      setState(() {
        _ticket = data;
        _replies = replies;
        final status = data['status']?.toString().toLowerCase();
        if (status != null && status.isNotEmpty) {
          _selectedStatus = status == 'in_progress' ? 'onprogress' : status;
        }
        _isLoading = false;
        _errorMessage = null;
      });

      if (scrollToBottom) _scheduleScrollToBottom();
    } else {
      setState(() {
        _isLoading = false;
        // Saat polling gagal, jangan timpa tampilan yang sudah ada.
        if (!silent || _ticket == null) {
          _errorMessage = _messageFrom(
            res,
            'Tiket tidak bisa dimuat. Silakan coba lagi.',
          );
        }
      });
    }
  }

  void _scheduleScrollToBottom({bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  Future<void> _pickReplyAttachments() async {
    final picked = await pickAttachments();
    if (!mounted || picked.isEmpty) return;

    setState(() {
      _pendingAttachments = [
        ..._pendingAttachments,
        ...picked,
      ].take(5).toList();
    });
  }

  Future<void> _handleSendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _isSending) return;

    FocusScope.of(context).unfocus();
    setState(() => _isSending = true);

    final res = await ApiService.sendReply(
      widget.ticketCode,
      text,
      isInternal: _isInternalNote,
    );

    if (!mounted) return;

    if (res['status'] != 200 && res['status'] != 201) {
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _messageFrom(res, 'Gagal mengirim balasan. Coba lagi.'),
          ),
        ),
      );
      return;
    }

    // Lampiran baru bisa ditempelkan setelah balasan punya id.
    final replyId = _replyIdFrom(res);
    final attachmentCount = _pendingAttachments.length;
    var uploaded = 0;

    if (_pendingAttachments.isNotEmpty && replyId != null) {
      setState(() => _isUploading = true);

      for (final file in _pendingAttachments) {
        final upload = await ApiService.uploadAttachment(
          widget.ticketCode,
          bytes: file.bytes,
          filename: file.name,
          replyId: replyId,
        );
        if (upload['status'] == 201) uploaded++;
      }
    }

    if (!mounted) return;

    setState(() {
      _isSending = false;
      _isUploading = false;
      _pendingAttachments = [];
      _isInternalNote = false;
    });

    _replyController.clear();

    if (attachmentCount > 0) {
      final message = uploaded == attachmentCount
          ? '$uploaded lampiran terkirim.'
          : '$uploaded dari $attachmentCount lampiran terkirim.';

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }

    await _loadDetail();
  }

  String? _replyIdFrom(Map<String, dynamic> response) {
    final payload = response['data'];
    final body = payload is Map ? payload['data'] : null;
    final id = body is Map ? body['id'] : null;
    return id?.toString();
  }

  /// Perubahan status langsung dikirim ke endpoint khusus, tanpa menunggu
  /// admin menulis balasan.
  Future<void> _changeStatus(String status) async {
    if (_isUpdatingStatus || _selectedStatus == status) return;

    final previous = _selectedStatus;

    setState(() {
      _selectedStatus = status;
      _isUpdatingStatus = true;
    });

    final res = await ApiService.updateTicketStatus(widget.ticketCode, status);
    if (!mounted) return;

    if (res['status'] == 200) {
      setState(() => _isUpdatingStatus = false);
      await _loadDetail(scrollToBottom: false, silent: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Status tiket diperbarui.'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      setState(() {
        _selectedStatus = previous;
        _isUpdatingStatus = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _messageFrom(res, 'Gagal mengubah status tiket. Coba lagi.'),
          ),
        ),
      );
    }
  }

  Future<void> _openAssignSheet() async {
    if (_admins.isEmpty) await _loadMeta();
    if (!mounted) return;

    final currentId = _ticket?['assigned_to'];

    final result = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
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
                'Penanggung jawab',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Pilih admin yang menangani tiket ini.',
                style: TextStyle(fontSize: 12.5, color: AppColors.muted),
              ),
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.person_off_outlined,
                  size: 20,
                  color: AppColors.muted,
                ),
                title: const Text(
                  'Belum ditugaskan',
                  style: TextStyle(fontSize: 14),
                ),
                trailing: currentId == null
                    ? const Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: AppColors.blue,
                      )
                    : null,
                onTap: () => Navigator.pop(context, 0),
              ),
              for (final raw in _admins)
                if (raw is Map)
                  Builder(
                    builder: (context) {
                      final id = int.tryParse(raw['id']?.toString() ?? '');
                      final isCurrent = id != null && id == currentId;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          radius: 15,
                          backgroundColor: AppColors.blueSoft,
                          child: Text(
                            _initials((raw['name'] ?? 'A').toString()),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.blueDark,
                            ),
                          ),
                        ),
                        title: Text(
                          (raw['name'] ?? 'Admin').toString(),
                          style: const TextStyle(fontSize: 14),
                        ),
                        trailing: isCurrent
                            ? const Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: AppColors.blue,
                              )
                            : null,
                        onTap: id == null
                            ? null
                            : () => Navigator.pop(context, id),
                      );
                    },
                  ),
            ],
          ),
        ),
      ),
    );

    if (result == null) return;

    final assignedTo = result == 0 ? null : result;
    final res = await ApiService.assignTicket(widget.ticketCode, assignedTo);
    if (!mounted) return;

    if (res['status'] == 200) {
      await _loadDetail(scrollToBottom: false, silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Penanggung jawab diperbarui.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _messageFrom(res, 'Gagal menetapkan penanggung jawab.'),
          ),
        ),
      );
    }
  }

  Future<void> _openCsatDialog() async {
    final result = await showDialog<({int rating, String comment})>(
      context: context,
      builder: (context) => const _CsatDialog(),
    );

    if (result == null) return;

    final res = await ApiService.submitCsat(
      widget.ticketCode,
      rating: result.rating,
      comment: result.comment,
    );

    if (!mounted) return;

    if (res['status'] == 200) {
      await _loadDetail(scrollToBottom: false, silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Terima kasih atas penilaianmu.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_messageFrom(res, 'Gagal menyimpan penilaian.')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Detail tiket',
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              '#${widget.ticketCode}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.muted,
              ),
            ),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  bool get _canRate {
    final ticket = _ticket;
    if (ticket == null || _userRole == 'admin') return false;
    if ((ticket['status'] ?? '').toString().toLowerCase() != 'resolved') {
      return false;
    }
    return ticket['csat_rating'] == null;
  }

  Widget _buildBody() {
    if (_isLoading && _ticket == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_ticket == null) {
      return Center(
        child: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Tiket tidak bisa dibuka',
          message: _errorMessage ?? 'Terjadi kesalahan saat memuat tiket.',
          actionLabel: 'Coba lagi',
          onAction: _loadDetail,
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _loadDetail(scrollToBottom: false),
            child: CustomScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  sliver: SliverToBoxAdapter(
                    child: _TicketHeader(
                      ticket: _ticket!,
                      isAdmin: _userRole == 'admin',
                      onAssign: _openAssignSheet,
                    ),
                  ),
                ),
                if (_canRate)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    sliver: SliverToBoxAdapter(
                      child: _CsatBanner(onTap: _openCsatDialog),
                    ),
                  ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        const Text(
                          'Percakapan',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.1,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.slateSoft,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${_replies.length}',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_replies.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: EmptyState(
                        icon: Icons.forum_outlined,
                        title: 'Belum ada balasan',
                        message:
                            'Tim support akan membalas tiket ini secepatnya.',
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                    sliver: SliverList.builder(
                      itemCount: _replies.length,
                      itemBuilder: (context, index) {
                        final reply = _asMap(_replies[index]);
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: index == _replies.length - 1 ? 0 : 14,
                          ),
                          child: _ReplyBubble(
                            reply: reply,
                            isOwn: _isOwnReply(reply),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        _buildComposer(),
      ],
    );
  }

  Widget _buildComposer() {
    final canSend = _replyController.text.trim().isNotEmpty && !_isSending;
    final assignee = _asMap(_ticket?['assignee']);
    final assigneeName = (assignee['name'] ?? '').toString();

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_userRole == 'admin') ...[
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(right: 10, top: 5),
                        child: Text(
                          'Status tiket',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                      for (final status in _statuses)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            selected: _selectedStatus == status.value,
                            showCheckmark: false,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            label: Text(status.label),
                            labelStyle: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: _selectedStatus == status.value
                                  ? AppColors.blueDark
                                  : AppColors.muted,
                            ),
                            visualDensity: VisualDensity.compact,
                            onSelected: _isUpdatingStatus
                                ? null
                                : (_) => _changeStatus(status.value),
                          ),
                        ),
                      if (_isUpdatingStatus)
                        const Padding(
                          padding: EdgeInsets.only(top: 8, left: 2),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 32,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(
                            Icons.sticky_note_2_outlined,
                            size: 15,
                            color: _isInternalNote
                                ? AppColors.amber
                                : AppColors.muted,
                          ),
                          label: const Text('Catatan internal'),
                          labelStyle: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _isInternalNote
                                ? AppColors.amber
                                : AppColors.muted,
                          ),
                          backgroundColor: _isInternalNote
                              ? AppColors.amberSoft
                              : AppColors.white,
                          side: BorderSide(
                            color: _isInternalNote
                                ? AppColors.amber
                                : AppColors.line,
                          ),
                          onPressed: () => setState(
                            () => _isInternalNote = !_isInternalNote,
                          ),
                        ),
                      ),
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        avatar: const Icon(
                          Icons.person_add_alt_1_rounded,
                          size: 15,
                          color: AppColors.muted,
                        ),
                        label: Text(
                          assigneeName.isEmpty
                              ? 'Tugaskan'
                              : 'Ditangani: $assigneeName',
                        ),
                        labelStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.muted,
                        ),
                        onPressed: _openAssignSheet,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_pendingAttachments.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < _pendingAttachments.length; i++)
                        InputChip(
                          visualDensity: VisualDensity.compact,
                          label: SizedBox(
                            width: 120,
                            child: Text(
                              _pendingAttachments[i].name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          labelStyle: const TextStyle(fontSize: 10.5),
                          onDeleted: () {
                            final next = [..._pendingAttachments];
                            next.removeAt(i);
                            setState(() => _pendingAttachments = next);
                          },
                          deleteIcon: const Icon(Icons.close_rounded, size: 14),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_isInternalNote)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6, left: 2),
                  child: Row(
                    children: [
                      Icon(
                        Icons.visibility_off_outlined,
                        size: 13,
                        color: AppColors.amber,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'Catatan ini hanya terlihat oleh admin.',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: AppColors.amber,
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 4, bottom: 4),
                    child: IconButton(
                      tooltip: 'Lampirkan file',
                      onPressed: _isSending ? null : _pickReplyAttachments,
                      icon: Icon(
                        Icons.attach_file_rounded,
                        size: 20,
                        color: _pendingAttachments.isEmpty
                            ? AppColors.muted
                            : AppColors.blue,
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _replyController,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.send,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _handleSendReply(),
                      decoration: InputDecoration(
                        hintText: _isUploading
                            ? 'Mengunggah lampiran...'
                            : _isInternalNote
                            ? 'Tulis catatan internal...'
                            : 'Tulis balasan...',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(color: AppColors.line),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(color: AppColors.line),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(22),
                          borderSide: const BorderSide(
                            color: AppColors.blue,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: Material(
                      color: canSend ? AppColors.blue : AppColors.slateSoft,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: canSend ? _handleSendReply : null,
                        borderRadius: BorderRadius.circular(14),
                        child: Center(
                          child: _isSending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.blue,
                                  ),
                                )
                              : Icon(
                                  Icons.arrow_upward_rounded,
                                  size: 20,
                                  color: canSend
                                      ? Colors.white
                                      : AppColors.muted,
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isOwnReply(Map<String, dynamic> reply) {
    final sender = _asMap(reply['user']);
    final senderId = sender['id']?.toString();
    final senderName = sender['name']?.toString();

    if (_currentUserId != null && senderId != null) {
      return senderId == _currentUserId;
    }

    if (_currentUserName != null && senderName != null) {
      return senderName == _currentUserName;
    }

    final senderRole = (sender['role'] ?? 'user').toString().toLowerCase();
    return _userRole == 'admin' ? senderRole == 'admin' : senderRole == 'user';
  }
}

class _TicketHeader extends StatelessWidget {
  final Map<String, dynamic> ticket;
  final bool isAdmin;
  final VoidCallback onAssign;

  const _TicketHeader({
    required this.ticket,
    required this.isAdmin,
    required this.onAssign,
  });

  @override
  Widget build(BuildContext context) {
    final title = (ticket['title'] ?? 'Tanpa judul').toString();
    final description = (ticket['description'] ?? '').toString();
    final status = (ticket['status'] ?? 'open').toString();
    final priority = (ticket['priority'] ?? '').toString();
    final createdAt = (ticket['created_at'] ?? '').toString();
    final requester = _asMap(ticket['user']);
    final requesterName = requester['name']?.toString();
    final categoryLabel = (ticket['category_label'] ?? '').toString();
    final dueAt = ticket['due_at']?.toString();
    final slaStatus = ticket['sla_status']?.toString();
    final assignee = _asMap(ticket['assignee']);
    final assigneeName = (assignee['name'] ?? '').toString();
    final attachments = ticket['attachments'] is List
        ? ticket['attachments'] as List
        : const <dynamic>[];
    final csatRating = int.tryParse(ticket['csat_rating']?.toString() ?? '');
    final csatComment = (ticket['csat_comment'] ?? '').toString();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusBadge(status: status),
              if (priority.isNotEmpty) PriorityBadge(priority: priority),
              SlaBadge(dueAt: dueAt, slaStatus: slaStatus),
            ],
          ),
          if (categoryLabel.isNotEmpty) ...[
            const SizedBox(height: 9),
            Row(
              children: [
                const Icon(
                  Icons.folder_outlined,
                  size: 13,
                  color: AppColors.muted,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    categoryLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontSize: 19,
              height: 1.3,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: AppColors.ink,
            ),
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              description,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.6,
                color: AppColors.muted,
              ),
            ),
          ],
          if (attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            AttachmentList(attachments: attachments),
          ],
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Divider(height: 1),
          ),
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 14,
                color: AppColors.muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  formatDateTime(createdAt),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.muted,
                  ),
                ),
              ),
              if (requesterName != null && requesterName.isNotEmpty) ...[
                const Icon(
                  Icons.person_outline_rounded,
                  size: 14,
                  color: AppColors.muted,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    requesterName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: isAdmin ? onAssign : null,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 1),
              child: Row(
                children: [
                  const Icon(
                    Icons.assignment_ind_outlined,
                    size: 15,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Penanggung jawab',
                    style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      assigneeName.isEmpty ? 'Belum ditugaskan' : assigneeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: assigneeName.isEmpty
                            ? AppColors.muted
                            : AppColors.ink,
                      ),
                    ),
                  ),
                  if (isAdmin)
                    const Icon(
                      Icons.edit_outlined,
                      size: 14,
                      color: AppColors.blue,
                    ),
                ],
              ),
            ),
          ),
          if (csatRating != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _Stars(rating: csatRating),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    csatComment.isEmpty ? 'Penilaian pelanggan' : csatComment,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  final int rating;

  const _Stars({required this.rating});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            i <= rating ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 14,
            color: i <= rating ? AppColors.amber : AppColors.line,
          ),
      ],
    );
  }
}

class _ReplyBubble extends StatelessWidget {
  final Map<String, dynamic> reply;
  final bool isOwn;

  const _ReplyBubble({required this.reply, required this.isOwn});

  @override
  Widget build(BuildContext context) {
    final sender = _asMap(reply['user']);
    final senderName = (sender['name'] ?? 'Pengguna').toString();
    final content = (reply['content'] ?? '').toString();
    final createdAt = (reply['created_at'] ?? '').toString();
    final isInternal = reply['is_internal'] == true;
    final attachments = reply['attachments'] is List
        ? reply['attachments'] as List
        : const <dynamic>[];
    final isBlueBubble = isOwn && !isInternal;

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: math.min(MediaQuery.of(context).size.width * 0.72, 560),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: isInternal
            ? AppColors.amberSoft
            : isOwn
            ? AppColors.blue
            : AppColors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(isOwn ? 16 : 4),
          topRight: Radius.circular(isOwn ? 4 : 16),
          bottomLeft: const Radius.circular(16),
          bottomRight: const Radius.circular(16),
        ),
        border: isInternal
            ? Border.all(color: AppColors.amber.withValues(alpha: 0.35))
            : isOwn
            ? null
            : Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isInternal) ...[
            const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.sticky_note_2_outlined,
                  size: 12,
                  color: AppColors.amber,
                ),
                SizedBox(width: 4),
                Text(
                  'Catatan internal',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.amber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          Text(
            content,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: isBlueBubble ? Colors.white : AppColors.ink,
            ),
          ),
          if (attachments.isNotEmpty) ...[
            const SizedBox(height: 8),
            AttachmentList(
              attachments: attachments,
              compact: true,
              onColor: isBlueBubble ? Colors.white : null,
            ),
          ],
          const SizedBox(height: 5),
          Text(
            formatDateTime(createdAt),
            style: TextStyle(
              fontSize: 10,
              color: isBlueBubble
                  ? Colors.white.withValues(alpha: 0.7)
                  : AppColors.muted,
            ),
          ),
        ],
      ),
    );

    if (isOwn) {
      return Align(
        alignment: Alignment.centerRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              isInternal ? 'Catatan internal · Kamu' : 'Kamu',
              style: const TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 4),
            bubble,
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.greenSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            _initials(senderName),
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: AppColors.greenDark,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                senderName,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 4),
              bubble,
            ],
          ),
        ),
      ],
    );
  }
}

class _CsatBanner extends StatelessWidget {
  final VoidCallback onTap;

  const _CsatBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: AppColors.blueSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.star_rounded, size: 22, color: AppColors.blue),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bagaimana layanan kami?',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.blueDark,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Tiket sudah selesai. Beri penilaian singkat.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 36),
            ),
            child: const Text('Beri nilai'),
          ),
        ],
      ),
    );
  }
}

class _CsatDialog extends StatefulWidget {
  const _CsatDialog();

  @override
  State<_CsatDialog> createState() => _CsatDialogState();
}

class _CsatDialogState extends State<_CsatDialog> {
  final _commentController = TextEditingController();
  int _rating = 0;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nilai layanan'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Seberapa puas kamu dengan penanganan tiket ini?',
            style: TextStyle(fontSize: 13, height: 1.5, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  onPressed: () => setState(() => _rating = i),
                  icon: Icon(
                    i <= _rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 32,
                    color: i <= _rating ? AppColors.amber : AppColors.line,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _commentController,
            maxLines: 3,
            maxLength: 500,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Ceritakan pengalamanmu (opsional)',
              counterText: '',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        TextButton(
          onPressed: _rating == 0
              ? null
              : () => Navigator.pop(context, (
                  rating: _rating,
                  comment: _commentController.text.trim(),
                )),
          child: const Text('Kirim'),
        ),
      ],
    );
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
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

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();

  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();

  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}
