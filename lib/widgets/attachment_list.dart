import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';

/// Baris/grid lampiran tiket. Gambar ditampilkan sebagai thumbnail,
/// file lain sebagai kartu yang bisa dibuka di aplikasi eksternal.
class AttachmentList extends StatelessWidget {
  final List<dynamic> attachments;
  final bool compact;
  final Color? onColor;

  const AttachmentList({
    super.key,
    required this.attachments,
    this.compact = false,
    this.onColor,
  });

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: attachments
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .map(
            (item) => _AttachmentTile(
              attachment: item,
              compact: compact,
              onColor: onColor,
            ),
          )
          .toList(),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  final Map<String, dynamic> attachment;
  final bool compact;
  final Color? onColor;

  const _AttachmentTile({
    required this.attachment,
    required this.compact,
    this.onColor,
  });

  @override
  Widget build(BuildContext context) {
    final path = (attachment['url'] ?? '').toString();
    final name = (attachment['name'] ?? 'Lampiran').toString();
    final isImage = attachment['is_image'] == true;
    final size = _formatSize(attachment['size']);
    final url = path.isEmpty ? '' : ApiService.absoluteUrl(path);

    if (isImage && url.isNotEmpty) {
      return _ImageAttachment(url: url, name: name, size: compact ? 68 : 84);
    }

    final fg = onColor ?? AppColors.ink;

    return Material(
      color: onColor != null
          ? Colors.white.withValues(alpha: 0.14)
          : AppColors.canvas,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context, url),
        child: Container(
          constraints: BoxConstraints(maxWidth: compact ? 220 : 260),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: onColor?.withValues(alpha: 0.3) ?? AppColors.line,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_iconFor(name), size: 18, color: onColor ?? AppColors.blue),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: fg,
                      ),
                    ),
                    if (size.isNotEmpty)
                      Text(
                        size,
                        style: TextStyle(
                          fontSize: 10,
                          color:
                              onColor?.withValues(alpha: 0.75) ??
                              AppColors.muted,
                        ),
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

  Future<void> _open(BuildContext context, String url) async {
    if (url.isEmpty) return;

    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lampiran tidak bisa dibuka.')),
      );
    }
  }
}

class _ImageAttachment extends StatelessWidget {
  final String url;
  final String name;
  final double size;

  const _ImageAttachment({
    required this.url,
    required this.name,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _preview(context),
      child: Hero(
        tag: 'attachment-$url',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: size,
            height: size,
            color: AppColors.canvas,
            child: Image.network(
              url,
              fit: BoxFit.cover,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
              errorBuilder: (context, error, stack) => Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 20,
                  color: AppColors.muted.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _preview(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.85),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(url, fit: BoxFit.contain),
            ),
            const SizedBox(height: 12),
            Text(
              name,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _iconFor(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
  return Icons.insert_drive_file_outlined;
}

String _formatSize(dynamic raw) {
  final bytes = int.tryParse(raw?.toString() ?? '') ?? 0;
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
