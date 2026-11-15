const _namaBulan = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];

/// Format ISO-8601 dari API menjadi "28 Mei 2026, 09:42" (waktu lokal).
/// Jika format tidak dikenali, teks asli dikembalikan apa adanya.
String formatDateTime(dynamic raw) {
  if (raw == null) return '';
  final value = raw.toString().trim();
  if (value.isEmpty) return '';

  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;

  final local = parsed.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = _namaBulan[local.month - 1];
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');

  return '$day $month ${local.year}, $hour:$minute';
}

/// Sama seperti [formatDateTime] tanpa bagian jam.
String formatDate(dynamic raw) {
  if (raw == null) return '';
  final value = raw.toString().trim();
  if (value.isEmpty) return '';

  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;

  final local = parsed.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = _namaBulan[local.month - 1];

  return '$day $month ${local.year}';
}
