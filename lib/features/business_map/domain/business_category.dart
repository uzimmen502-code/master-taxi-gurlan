import 'package:flutter/material.dart';

/// Тадбиркорлик объекти тури гуруҳи (docs/biznes_xaritasi_2026-10-23_uz.md, B-10 — PROPOSED).
///
/// Рўйхат `functions/business_directory.js` даги `CATEGORIES` билан БИР ХИЛ бўлиши шарт (сервер ёзувда шу рўйхат
/// бўйича текширади); паритетни `business_category_test.dart` қулфлайди. Матн калити: `business_cat_<wire>` (3 тилда).
///
/// [color] — тур ранги (эга, 2026-10-23: «барча фаолият турлари турли ранглар билан»): чип ва харитадаги маркер
/// БИР хил ранг. 14 та ранг бир-биридан фарқ қилади (тест қулфлайди); устидаги ок иконка бу рангларда ўқилади.
enum BusinessCategory {
  retail('retail', Icons.storefront_rounded, Color(0xFFF59E0B)),
  wholesale('wholesale', Icons.warehouse_outlined, Color(0xFF0EA5E9)),
  food('food', Icons.restaurant_rounded, Color(0xFFEF4444)),
  auto('auto', Icons.directions_car_filled_rounded, Color(0xFF6366F1)),
  manufacturing('manufacturing', Icons.factory_rounded, Color(0xFF92400E)),
  personal('personal', Icons.content_cut_rounded, Color(0xFFEC4899)),
  homeServices('home_services', Icons.handyman_rounded, Color(0xFF14B8A6)),
  health('health', Icons.local_hospital_rounded, Color(0xFF22C55E)),
  education('education', Icons.school_rounded, Color(0xFF8B5CF6)),
  leisure('leisure', Icons.beach_access_rounded, Color(0xFF06B6D4)),
  logistics('logistics', Icons.local_shipping_rounded, Color(0xFF84CC16)),
  professional('professional', Icons.business_center_rounded, Color(0xFF1D4ED8)),
  itMedia('it_media', Icons.computer_rounded, Color(0xFF475569)),
  other('other', Icons.category_rounded, Color(0xFF9CA3AF));

  const BusinessCategory(this.wire, this.icon, this.color);

  /// Серверга юбориладиган/Firestore'да сақланадиган қиймат.
  final String wire;
  final IconData icon;
  final Color color;

  String get labelKey => 'business_cat_$wire';

  /// Номаълум/бўш қиймат (эски ёки бузилган ҳужжат) — `other`; харита синмайди (26-банд).
  static BusinessCategory fromWire(Object? raw) {
    final s = (raw ?? '').toString().trim();
    for (final c in values) {
      if (c.wire == s) return c;
    }
    return BusinessCategory.other;
  }

  static List<String> get wires => [for (final c in values) c.wire];
}
