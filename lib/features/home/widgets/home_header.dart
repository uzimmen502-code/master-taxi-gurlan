import 'package:flutter/material.dart';

import '../../../core/utils/daily_duas.dart';

/// Bugungi duo — 1-qator arabcha, 2-qator o‘zbekcha.
class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  static const _textPrimary = Color(0xFFF5F5FA);
  static const _textArabic = Color(0xFFB8B8D0);

  @override
  Widget build(BuildContext context) {
    final dua = todayDua();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            dua.ar,
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _textArabic,
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
