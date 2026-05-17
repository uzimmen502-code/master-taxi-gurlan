import 'package:flutter/material.dart';

import '../../../core/utils/daily_duas.dart';
import '../controllers/home_controller.dart';

/// Юқори сарлавҳа — эски "Салом + Аллоҳ ҳимояси" блоки ўрнига **бугунги дуо**
/// (арабча матн + ўзбекча таржима). Профил аватари ҳамон ўнг тарафда.
///
/// Дизайн қарорлари:
///   - Кўнгилни кўтарувчи семантика — ҳар куни янги дуо асосий саҳифа тепасида.
///   - Шрифт оқ ранг + кичик нур-кўлага — яшил градиент устида яхши ўқилади.
class HomeHeader extends StatelessWidget {
  const HomeHeader({
    super.key,
    required this.controller,
    required this.onProfileTap,
    this.onOpenAdminWeb,
  });

  final HomeController controller;
  final VoidCallback onProfileTap;

  /// Вебда (бир хостда `/admin/`) — яратувчи учун админга ўтиш.
  final VoidCallback? onOpenAdminWeb;

  @override
  Widget build(BuildContext context) {
    final dua = todayDua();
    final name = controller.name;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                dua.ar,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1.7,
                  shadows: [Shadow(color: Colors.black38, blurRadius: 4)],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                dua.uz,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.92),
                  fontStyle: FontStyle.italic,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (onOpenAdminWeb != null) ...[
          Tooltip(
            message: 'Админ панели',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onOpenAdminWeb,
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Colors.white70, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.admin_panel_settings_outlined,
                        color: Colors.white,
                        size: 22,
                      ),
                      if (MediaQuery.sizeOf(context).width >= 560) ...[
                        const SizedBox(width: 6),
                        const Text(
                          'Админ',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            shadows: [
                              Shadow(color: Colors.black38, blurRadius: 3),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        GestureDetector(
          onTap: onProfileTap,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
