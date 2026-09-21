import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import 'ticket_detail_screen.dart';
import 'create_ticket_screen.dart';

class TicketListScreen extends StatefulWidget {
  const TicketListScreen({super.key});

  @override
  State<TicketListScreen> createState() => _TicketListScreenState();
}

class _TicketListScreenState extends State<TicketListScreen> {
  List<dynamic> _tickets = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _selectedStatus;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    _loadUserRoleAndFetch();
  }

  Future<void> _loadUserRoleAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _userRole = prefs.getString('role');
      });
    }
    _fetchTickets();
  }

  Future<void> _fetchTickets() async {
    setState(() => _isLoading = true);

    final response = await ApiService.getTickets(
      search: _searchQuery.isNotEmpty ? _searchQuery : null,
      status: _selectedStatus,
    );

    debugPrint("=== RESPONS API TICKETS ===");
    debugPrint("STATUS CODE: ${response['status']}");
    debugPrint("RAW DATA: ${response['data']}");

    if (mounted) {
      setState(() {
        if (response != null) {
          var resData = response['data'] ?? response;

          // Parsing data serbaguna (mendukung array langsung maupun objek bertingkat)
          if (resData is List) {
            _tickets = resData;
          } else if (resData is Map) {
            if (resData['data'] != null && resData['data'] is List) {
              _tickets = resData['data'];
            } else if (resData['tickets'] != null && resData['tickets'] is List) {
              _tickets = resData['tickets'];
            } else if (resData['data'] != null && resData['data'] is Map && resData['data']['data'] is List) {
              _tickets = resData['data']['data'];
            } else {
              _tickets = [];
            }
          } else {
            _tickets = [];
          }
        } else {
          _tickets = [];
        }
        _isLoading = false;
      });
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return Colors.orange;
      case 'onprogress':
      case 'in_progress':
        return Colors.blue;
      case 'resolved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // Helper untuk Merapikan Format Tanggal
  String _formatDate(String rawDate) {
    if (rawDate.isEmpty) return '';
    try {
      DateTime parsedDate = DateTime.parse(rawDate).toLocal();
      String day = parsedDate.day.toString().padLeft(2, '0');
      String month = parsedDate.month.toString().padLeft(2, '0');
      String year = parsedDate.year.toString();
      String hour = parsedDate.hour.toString().padLeft(2, '0');
      String minute = parsedDate.minute.toString().padLeft(2, '0');

      return '$day/$month/$year $hour:$minute';
    } catch (e) {
      return rawDate;
    }
  }

  // WIDGET CARD TIKET DENGAN BADGE NOTIFIKASI & TANGGAL RAPI
  Widget _buildTicketCard(Map<String, dynamic> ticket) {
    int unreadCount = 0;
    if (ticket['unread_replies_count'] != null) {
      unreadCount = int.tryParse(ticket['unread_replies_count'].toString()) ?? 0;
    } else if (ticket['unread_count'] != null) {
      unreadCount = int.tryParse(ticket['unread_count'].toString()) ?? 0;
    }

    String status = (ticket['status'] ?? 'open').toString();
    String title = ticket['title'] ?? ticket['judul'] ?? 'Tanpa Judul';
    String code = ticket['code'] ?? ticket['kode'] ?? '';
    String rawCreatedAt = ticket['created_at'] ?? ticket['tanggal'] ?? '';
    String formattedDate = _formatDate(rawCreatedAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Detail Informasi Kiri
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 6),
                Text('Kode: $code', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                if (formattedDate.isNotEmpty)
                  Text(
                    'Tanggal: $formattedDate',
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),

          // Status & Badge Notifikasi Kanan
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Badge Notifikasi Balasan Baru
              if (unreadCount > 0)
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 10),
                      const SizedBox(width: 4),
                      Text(
                        '$unreadCount pesan baru',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

              // Chip Status Tiket
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _getStatusColor(status).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    color: _getStatusColor(status),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support Center', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchTickets,
          ),
        ],
      ),
      floatingActionButton: _userRole != 'admin'
          ? FloatingActionButton.extended(
              onPressed: () async {
                final isCreated = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const CreateTicketScreen()),
                );
                if (isCreated == true) _fetchTickets();
              },
              icon: const Icon(Icons.add),
              label: const Text('Buat Tiket'),
            )
          : null,
      body: Column(
        children: [
          // Filter & Search Bar
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Cari kode...',
                      prefixIcon: const Icon(Icons.search),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onSubmitted: (val) {
                      _searchQuery = val;
                      _fetchTickets();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String?>(
                  value: _selectedStatus,
                  hint: const Text('Semua'),
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Semua')),
                    DropdownMenuItem(value: 'open', child: Text('Open')),
                    DropdownMenuItem(value: 'onprogress', child: Text('Onprogress')),
                    DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
                    DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                  ],
                  onChanged: (val) {
                    setState(() => _selectedStatus = val);
                    _fetchTickets();
                  },
                ),
              ],
            ),
          ),

          // Stream / List Tiket
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _fetchTickets,
                    child: _tickets.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.inbox_outlined, size: 60, color: Colors.grey),
                                const SizedBox(height: 12),
                                Text(
                                  _selectedStatus != null
                                      ? 'Tidak ada tiket dengan status "$_selectedStatus"'
                                      : 'Belum ada tiket yang dibuat.',
                                  style: const TextStyle(color: Colors.grey),
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      _selectedStatus = null;
                                      _searchQuery = '';
                                    });
                                    _fetchTickets();
                                  },
                                  icon: const Icon(Icons.filter_alt_off),
                                  label: const Text('Reset Filter / Tampilkan Semua'),
                                )
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            itemCount: _tickets.length,
                            itemBuilder: (context, index) {
                              final ticket = Map<String, dynamic>.from(_tickets[index]);
                              final code = ticket['code'] ?? ticket['kode'] ?? '';

                              return InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => TicketDetailScreen(ticketCode: code),
                                    ),
                                  );
                                  _fetchTickets();
                                },
                                child: _buildTicketCard(ticket),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}