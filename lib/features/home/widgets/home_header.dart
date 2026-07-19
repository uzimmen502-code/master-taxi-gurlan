import 'package:flutter/material.dart';

import '../../../core/brand_labels.dart';
import '../../../core/utils/daily_duas.dart';

/// Home yuqori: AVA Zona + tuman, keyin bugungi duo (ochiq fon).
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  static const _brand = Color(0xFF1A3A20);
  static const _district = Color(0xFF2E7D32);
  static const _textPrimary = Color(0xFF1A3A20);
  static const _textSecondary = Color(0xFF4A6741);

  @override
  Widget build(BuildContext context) {
    final dua = todayDua();
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BrandTitleColumn(
            brandStyle: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: _brand,
            ),
            districtStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
              color: _district,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            dua.ar,
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _textSecondary,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            dua.uz,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }
}
