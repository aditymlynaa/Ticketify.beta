import 'package:file_picker/file_picker.dart';

/// Satu file yang dipilih dari perangkat sebelum diunggah.
class PickedAttachment {
  final String name;
  final List<int> bytes;

  const PickedAttachment({required this.name, required this.bytes});
}

/// Batas ukuran mengikuti konfigurasi backend (5 MB).
const _maxBytes = 5 * 1024 * 1024;

/// Maksimal file yang bisa dilampirkan sekaligus.
const _maxFiles = 5;

/// Buka pemilih file dan kembalikan file yang siap diunggah.
Future<List<PickedAttachment>> pickAttachments() async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
  );

  final picked = <PickedAttachment>[];

  for (final file in files.take(_maxFiles)) {
    final size = file.lengthSync() ?? await file.length() ?? 0;
    if (size <= 0 || size > _maxBytes) continue;

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) continue;

    picked.add(PickedAttachment(name: file.name, bytes: bytes));
  }

  return picked;
}
