import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Logo aplikasi: kotak biru dengan aksen hijau kecil.
///
/// Sengaja dibuat sederhana (tanpa gradient/glassmorphism) supaya tetap
/// terlihat rapi di ukuran kecil maupun besar.
class AppLogo extends StatelessWidget {
  final double size;

  const AppLogo({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    final radius = size * 0.3;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppColors.blue,
              borderRadius: BorderRadius.circular(radius),
            ),
            child: Icon(
              Icons.confirmation_number_rounded,
              color: Colors.white,
              size: size * 0.54,
            ),
          ),
          Positioned(
            right: -size * 0.06,
            bottom: -size * 0.06,
            child: Container(
              width: size * 0.32,
              height: size * 0.32,
              decoration: BoxDecoration(
                color: AppColors.green,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.white, width: size * 0.06),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Logo + nama aplikasi untuk header.
class AppBrand extends StatelessWidget {
  final double logoSize;
  final bool showTagline;
  final Color taglineColor;

  const AppBrand({
    super.key,
    this.logoSize = 38,
    this.showTagline = true,
    this.taglineColor = AppColors.muted,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogo(size: logoSize),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ticketify',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                color: AppColors.ink,
              ),
            ),
            if (showTagline) ...[
              const SizedBox(height: 1),
              Text(
                'SUPPORT CENTER',
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                  color: taglineColor,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
