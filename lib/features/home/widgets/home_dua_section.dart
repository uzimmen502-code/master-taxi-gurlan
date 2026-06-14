import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/daily_duas.dart';

/// Kunlik duo — karta yo‘q; chap matn, o‘ng quran + moon.
class HomeDuaSection extends StatelessWidget {
  const HomeDuaSection({super.key});

  @override
  Widget build(BuildContext context) {
    final dua = todayDua();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 12, 0),
      child: Row(
        // Matn ustun balandroq (3 qator); rasm 92px. `start` bo‘lsa rasm ostida
        // yashil bo‘sh joy qoladi — ticker uzoqroq tuyuladi. `end` — pastdan hizalanadi.
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dua.ar,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.arabicText,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  dua.uz,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primaryDark,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 96,
            height: 92,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: 0,
                  right: 0,
                  child: Image.asset(
                    'assets/images/moon.png',
                    width: 48,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  left: 0,
                  child: Image.asset(
                    'assets/images/quran.png',
                    width: 84,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.menu_book_rounded,
                      size: 64,
                      color: AppColors.primaryMid,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
