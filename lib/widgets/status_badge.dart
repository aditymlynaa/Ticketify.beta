import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Badge status tiket dengan titik warna sebagai penanda cepat.
class StatusBadge extends StatelessWidget {
  final String status;
  final bool compact;

  const StatusBadge({super.key, required this.status, this.compact = false});

  static ({String label, Color fg, Color bg}) styleFor(String status) {
    switch (status.toLowerCase()) {
      case 'open':
        return (label: 'Open', fg: AppColors.amber, bg: AppColors.amberSoft);
      case 'onprogress':
      case 'in_progress':
        return (
          label: 'Diproses',
          fg: AppColors.blueDark,
          bg: AppColors.blueSoft,
        );
      case 'resolved':
        return (
          label: 'Selesai',
          fg: AppColors.greenDark,
          bg: AppColors.greenSoft,
        );
      case 'rejected':
        return (label: 'Ditolak', fg: AppColors.red, bg: AppColors.redSoft);
      default:
        return (
          label: status.isEmpty ? 'Tidak diketahui' : status,
          fg: AppColors.muted,
          bg: AppColors.slateSoft,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = styleFor(status);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: style.fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            style.label,
            style: TextStyle(
              fontSize: compact ? 10.5 : 11.5,
              fontWeight: FontWeight.w600,
              color: style.fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge prioritas tiket.
class PriorityBadge extends StatelessWidget {
  final String priority;

  const PriorityBadge({super.key, required this.priority});

  static ({String label, Color fg, Color bg}) styleFor(String priority) {
    switch (priority.toLowerCase()) {
      case 'critical':
        return (label: 'Kritis', fg: AppColors.red, bg: AppColors.redSoft);
      case 'high':
        return (label: 'Tinggi', fg: AppColors.amber, bg: AppColors.amberSoft);
      case 'medium':
        return (
          label: 'Sedang',
          fg: AppColors.blueDark,
          bg: AppColors.blueSoft,
        );
      case 'low':
      default:
        return (label: 'Rendah', fg: AppColors.muted, bg: AppColors.slateSoft);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = styleFor(priority);
    final isEmpty = priority.isEmpty;

    if (isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        style.label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: style.fg,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}
