import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 1. Import SharedPreferences
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
  String? _selectedStatus; // Default null = menampilkan Semua Status
  String? _userRole;       // 2. Variabel penampung role

  @override
  void initState() {
    super.initState();
    _loadUserRoleAndFetch();
  }

  // 3. Fungsi untuk mengambil role lalu fetch data tiket
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
        if (response['status'] == 200 && response['data'] != null) {
          var resData = response['data'];

          // 1. Jika respons berupa Map yang membungkus key 'data'
          if (resData is Map) {
            if (resData.containsKey('data')) {
              var innerData = resData['data'];
              if (innerData is List) {
                _tickets = innerData;
              } else if (innerData is Map && innerData.containsKey('data')) {
                _tickets = innerData['data'] ?? [];
              } else {
                _tickets = [];
              }
            } else {
              _tickets = [];
            }
          } 
          // 2. Jika respons langsung berupa List Array
          else if (resData is List) {
            _tickets = resData;
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
      // 4. Tombol 'Buat Tiket' disembunyikan jika role == 'admin'
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
                      hintText: 'Cari kode ',
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
                              final ticket = _tickets[index];
                              final code = ticket['code'] ?? '';
                              final title = ticket['title'] ?? 'Tanpa Judul';
                              final status = (ticket['status'] ?? 'open').toString();
                              final createdAt = ticket['created_at'] ?? '';

                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  title: Text(
                                    title,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text('Kode: $code', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                                      if (createdAt.toString().isNotEmpty)
                                        Text('Tanggal: $createdAt', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                                    ],
                                  ),
                                  trailing: Container(
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
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => TicketDetailScreen(ticketCode: code),
                                      ),
                                    );
                                    _fetchTickets();
                                  },
                                ),
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