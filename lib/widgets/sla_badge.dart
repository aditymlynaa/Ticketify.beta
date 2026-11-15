import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/date_formatter.dart';

/// Badge sederhana untuk menunjukkan kondisi SLA tiket.
class SlaBadge extends StatelessWidget {
  final String? dueAt;
  final String? slaStatus;
  final bool compact;

  const SlaBadge({
    super.key,
    required this.dueAt,
    required this.slaStatus,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final status = (slaStatus ?? '').toLowerCase();

    if (dueAt == null ||
        dueAt!.isEmpty ||
        status.isEmpty ||
        status == 'closed') {
      return const SizedBox.shrink();
    }

    late final String label;
    late final Color fg;
    late final Color bg;

    switch (status) {
      case 'overdue':
        label = 'Lewat SLA';
        fg = AppColors.red;
        bg = AppColors.redSoft;
        break;
      case 'at_risk':
        label = 'Hampir lewat';
        fg = AppColors.amber;
        bg = AppColors.amberSoft;
        break;
      default:
        label = 'SLA aman';
        fg = AppColors.greenDark;
        bg = AppColors.greenSoft;
    }

    return Tooltip(
      message: 'Target selesai: ${formatDateTime(dueAt!)}',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 9,
          vertical: compact ? 3 : 4,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.timer_outlined, size: compact ? 11 : 12, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: compact ? 10 : 10.5,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
