import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../utils/attachment_picker.dart';
import '../widgets/inline_alert.dart';

class CreateTicketScreen extends StatefulWidget {
  const CreateTicketScreen({super.key});

  @override
  State<CreateTicketScreen> createState() => _CreateTicketScreenState();
}

class _CreateTicketScreenState extends State<CreateTicketScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  static const _priorities = <_PriorityOption>[
    _PriorityOption(
      value: 'low',
      label: 'Rendah',
      description: 'Tidak mendesak',
      icon: Icons.signal_cellular_alt_1_bar_rounded,
      color: AppColors.muted,
      background: AppColors.slateSoft,
    ),
    _PriorityOption(
      value: 'medium',
      label: 'Sedang',
      description: 'Perlu ditangani',
      icon: Icons.signal_cellular_alt_2_bar_rounded,
      color: AppColors.blue,
      background: AppColors.blueSoft,
    ),
    _PriorityOption(
      value: 'high',
      label: 'Tinggi',
      description: 'Mengganggu kerja',
      icon: Icons.signal_cellular_alt_rounded,
      color: AppColors.amber,
      background: AppColors.amberSoft,
    ),
    _PriorityOption(
      value: 'critical',
      label: 'Kritis',
      description: 'Layanan berhenti',
      icon: Icons.priority_high_rounded,
      color: AppColors.red,
      background: AppColors.redSoft,
    ),
  ];

  String _selectedPriority = 'low';
  bool _isLoading = false;
  String? _errorMessage;

  List<({String value, String label})> _categories = _defaultCategories;
  String? _selectedCategory;
  List<PickedAttachment> _attachments = [];

  static const _defaultCategories = <({String value, String label})>[
    (value: 'network', label: 'Jaringan'),
    (value: 'hardware', label: 'Perangkat'),
    (value: 'software', label: 'Aplikasi'),
    (value: 'billing', label: 'Tagihan'),
    (value: 'installation', label: 'Pemasangan'),
    (value: 'other', label: 'Lainnya'),
  ];

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final res = await ApiService.getTicketMeta();
    if (!mounted || res['status'] != 200) return;

    final payload = res['data'];
    final data = payload is Map ? payload['data'] : null;
    final raw = data is Map ? data['categories'] : null;

    if (raw is! List || raw.isEmpty) return;

    final loaded = raw
        .whereType<Map>()
        .map(
          (item) => (
            value: (item['value'] ?? '').toString(),
            label: (item['label'] ?? '').toString(),
          ),
        )
        .where((item) => item.value.isNotEmpty)
        .toList();

    if (loaded.isEmpty) return;

    setState(() {
      _categories = loaded;
      if (!_categories.any((item) => item.value == _selectedCategory)) {
        _selectedCategory = null;
      }
    });
  }

  Future<void> _pickFiles() async {
    final picked = await pickAttachments();
    if (!mounted || picked.isEmpty) return;

    setState(() {
      _attachments = [..._attachments, ...picked].take(5).toList();
    });
  }

  Future<void> _submitTicket() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await ApiService.createTicket(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim(),
      priority: _selectedPriority,
      category: _selectedCategory,
    );

    if (!mounted) return;

    if (res['status'] != 200 && res['status'] != 201) {
      setState(() {
        _isLoading = false;
        _errorMessage = _messageFrom(res, 'Gagal membuat tiket. Coba lagi.');
      });
      return;
    }

    final payload = res['data'];
    final body = payload is Map ? payload['data'] : null;
    final code = body is Map ? (body['code'] ?? '').toString() : '';

    var uploaded = 0;
    if (_attachments.isNotEmpty && code.isNotEmpty) {
      for (final file in _attachments) {
        final upload = await ApiService.uploadAttachment(
          code,
          bytes: file.bytes,
          filename: file.name,
        );
        if (upload['status'] == 201) uploaded++;
      }
    }

    if (!mounted) return;

    setState(() => _isLoading = false);

    final message = _attachments.isEmpty
        ? 'Tiket berhasil dibuat.'
        : uploaded == _attachments.length
        ? 'Tiket dibuat dengan ${_attachments.length} lampiran.'
        : 'Tiket dibuat, $uploaded dari ${_attachments.length} lampiran terunggah.';

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Buat tiket')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ceritakan kendala yang kamu alami supaya tim support bisa langsung menindaklanjuti.',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.6,
                  color: AppColors.muted,
                ),
              ),
              const SizedBox(height: 20),
              if (_errorMessage != null) ...[
                InlineAlert(message: _errorMessage!),
                const SizedBox(height: 20),
              ],
              const FieldLabel('Judul tiket'),
              TextFormField(
                controller: _titleController,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                maxLength: 120,
                decoration: const InputDecoration(
                  hintText: 'Ringkas masalahnya dalam satu kalimat',
                  counterText: '',
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Judul wajib diisi';
                  }
                  if (value.trim().length < 5) {
                    return 'Judul minimal 5 karakter';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),
              const FieldLabel(
                'Deskripsi',
                hint: 'semakin detail semakin baik',
              ),
              TextFormField(
                controller: _descriptionController,
                minLines: 5,
                maxLines: 8,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Jelaskan kronologi, pesan error, atau langkah yang sudah dicoba...',
                  alignLabelWithHint: true,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Deskripsi wajib diisi';
                  }
                  if (value.trim().length < 10) {
                    return 'Deskripsi minimal 10 karakter';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 18),
              const FieldLabel('Prioritas'),
              const SizedBox(height: 2),
              Column(
                children: [
                  _PriorityRow(
                    children: [
                      _PriorityTile(
                        option: _priorities[0],
                        selected: _selectedPriority == _priorities[0].value,
                        onTap: () => _selectPriority(_priorities[0].value),
                      ),
                      _PriorityTile(
                        option: _priorities[1],
                        selected: _selectedPriority == _priorities[1].value,
                        onTap: () => _selectPriority(_priorities[1].value),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _PriorityRow(
                    children: [
                      _PriorityTile(
                        option: _priorities[2],
                        selected: _selectedPriority == _priorities[2].value,
                        onTap: () => _selectPriority(_priorities[2].value),
                      ),
                      _PriorityTile(
                        option: _priorities[3],
                        selected: _selectedPriority == _priorities[3].value,
                        onTap: () => _selectPriority(_priorities[3].value),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const FieldLabel('Kategori', hint: 'opsional'),
              const SizedBox(height: 2),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in _categories)
                    ChoiceChip(
                      label: Text(category.label),
                      selected: _selectedCategory == category.value,
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _selectedCategory == category.value
                            ? AppColors.blueDark
                            : AppColors.muted,
                      ),
                      onSelected: (selected) {
                        setState(
                          () => _selectedCategory = selected
                              ? category.value
                              : null,
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 20),
              const FieldLabel('Lampiran', hint: 'opsional · maks 5 MB'),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.attach_file_rounded,
                          size: 18,
                          color: AppColors.muted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _attachments.isEmpty
                                ? 'Belum ada file dipilih.'
                                : '${_attachments.length} file siap diunggah.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.muted,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _attachments.length >= 5
                              ? null
                              : _pickFiles,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: const Size(0, 32),
                          ),
                          child: const Text('Pilih file'),
                        ),
                      ],
                    ),
                    if (_attachments.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < _attachments.length; i++)
                            InputChip(
                              label: Text(
                                _attachments[i].name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              labelStyle: const TextStyle(
                                fontSize: 11,
                                color: AppColors.ink,
                              ),
                              onDeleted: () {
                                final next = [..._attachments];
                                next.removeAt(i);
                                setState(() => _attachments = next);
                              },
                              deleteIcon: const Icon(
                                Icons.close_rounded,
                                size: 15,
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 6),
                    const Text(
                      'Format JPG, PNG, WEBP, atau PDF.',
                      style: TextStyle(fontSize: 10.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              ElevatedButton(
                onPressed: _isLoading ? null : _submitTicket,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Kirim tiket'),
              ),
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  'Tim support akan membalas melalui halaman detail tiket.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: AppColors.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectPriority(String value) {
    if (_selectedPriority == value) return;
    setState(() => _selectedPriority = value);
  }
}

class _PriorityOption {
  final String value;
  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final Color background;

  const _PriorityOption({
    required this.value,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.background,
  });
}

class _PriorityRow extends StatelessWidget {
  final List<Widget> children;

  const _PriorityRow({required this.children});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: children[0]),
          const SizedBox(width: 10),
          Expanded(child: children[1]),
        ],
      ),
    );
  }
}

class _PriorityTile extends StatelessWidget {
  final _PriorityOption option;
  final bool selected;
  final VoidCallback onTap;

  const _PriorityTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? option.background : AppColors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        hoverColor: option.background,
        splashColor: option.background,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? option.color : AppColors.line,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(option.icon, size: 17, color: option.color),
                  const Spacer(),
                  Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? option.color : AppColors.line,
                        width: 1.4,
                      ),
                    ),
                    child: selected
                        ? Center(
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: option.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                option.label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? option.color : AppColors.ink,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                option.description,
                style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _messageFrom(Map<String, dynamic> response, String fallback) {
  final data = response['data'];

  if (data is Map) {
    final errors = data['errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is List && first.isNotEmpty) return first.first.toString();
      return first.toString();
    }

    final message = data['message'];
    if (message != null && message.toString().trim().isNotEmpty) {
      return message.toString();
    }
  }

  return fallback;
}
