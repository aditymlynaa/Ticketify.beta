import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';

class TicketDetailScreen extends StatefulWidget {
  final String ticketCode;
  const TicketDetailScreen({super.key, required this.ticketCode});

  @override
  State<TicketDetailScreen> createState() => _TicketDetailScreenState();
}

class _TicketDetailScreenState extends State<TicketDetailScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _ticket;
  List<dynamic> _replies = [];
  final TextEditingController _replyController = TextEditingController();
  bool _isSending = false;

  // Variabel untuk menyimpan peran & status pilihan admin
  String _userRole = 'user';
  String _selectedStatus = 'onprogress';

  @override
  void initState() {
    super.initState();
    _loadUserRole();
    _loadDetail();
  }

  // Mengambil role user dari SharedPreferences
  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _userRole = prefs.getString('role') ?? 'user';
      });
    }
  }

  // Mengambil data detail tiket & balasan chat
  Future<void> _loadDetail() async {
    setState(() => _isLoading = true);
    final res = await ApiService.getTicketDetail(widget.ticketCode);
    if (mounted) {
      if (res['status'] == 200) {
        final data = res['data']['data'] ?? res['data'];
        setState(() {
          _ticket = data;
          _replies = data['replies'] ?? [];
          // Set pilihan dropdown awal sesuai status tiket saat ini
          if (data['status'] != null) {
            _selectedStatus = data['status'].toString().toLowerCase();
          }
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    }
  }

  // Fungsi Mengirim Balasan Chat
  Future<void> _handleSendReply() async {
    if (_replyController.text.trim().isEmpty) return;

    setState(() => _isSending = true);

    // Kirim parameter status HANYA jika role adalah admin
    final res = await ApiService.sendReply(
      widget.ticketCode,
      _replyController.text.trim(),
      status: _userRole == 'admin' ? _selectedStatus : null,
    );

    if (mounted) {
      setState(() => _isSending = false);
      if (res['status'] == 201 || res['status'] == 200) {
        _replyController.clear();
        _loadDetail(); // Refresh data obrolan & status
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['data']['message'] ?? 'Gagal mengirim balasan')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Tiket: ${widget.ticketCode}'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Info Header Tiket
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey[200],
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_ticket?['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 4),
                      Text('Deskripsi: ${_ticket?['description'] ?? ''}', style: TextStyle(color: Colors.grey[700])),
                      const SizedBox(height: 4),
                      Text('Status: ${_ticket?['status']?.toUpperCase() ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                    ],
                  ),
                ),

                // Area Chat / Obrolan
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _replies.length,
                    itemBuilder: (context, index) {
                      final reply = _replies[index];
                      final isUserReply = reply['user']?['role'] == 'user';

                      return Align(
                        alignment: isUserReply ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isUserReply ? Theme.of(context).primaryColor.withOpacity(0.85) : Colors.grey[300],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                reply['user']?['name'] ?? 'User',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  color: isUserReply ? Colors.white70 : Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                reply['content'] ?? '',
                                style: TextStyle(color: isUserReply ? Colors.white : Colors.black87),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Input Chat Balasan & Dropdown Status (Jika Admin)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // DROPDOWN PILIHAN STATUS (Hanya Tampil Jika User = Admin)
                      if (_userRole == 'admin') ...[
                        Row(
                          children: [
                            const Text('Set Status: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButton<String>(
                                value: _selectedStatus,
                                isExpanded: true,
                                underline: const SizedBox(),
                                items: const [
                                  DropdownMenuItem(value: 'open', child: Text('Open')),
                                  DropdownMenuItem(value: 'onprogress', child: Text('Onprogress')),
                                  DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
                                  DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _selectedStatus = val);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const Divider(),
                      ],

                      // Form Input Pesan Chat
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _replyController,
                              decoration: const InputDecoration(
                                hintText: 'Ketik balasan...',
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                          _isSending
                              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                              : IconButton(
                                  icon: Icon(Icons.send, color: Theme.of(context).primaryColor),
                                  onPressed: _handleSendReply,
                                ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}