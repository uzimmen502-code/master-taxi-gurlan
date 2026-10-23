import 'package:flutter/material.dart';

/// Тадбиркорлик объекти тури гуруҳи (docs/biznes_xaritasi_2026-10-23_uz.md, B-10 — PROPOSED).
///
/// Рўйхат `functions/business_directory.js` даги `CATEGORIES` билан БИР ХИЛ бўлиши шарт
/// (сервер ёзувда шу рўйхат бўйича текширади); паритетни `business_category_test.dart` қулфлайди.
/// Матн калити: `business_cat_<wire>` (3 тилда).
enum BusinessCategory {
  retail('retail', Icons.storefront_rounded),
  wholesale('wholesale', Icons.warehouse_outlined),
  food('food', Icons.restaurant_rounded),
  auto('auto', Icons.directions_car_filled_rounded),
  manufacturing('manufacturing', Icons.factory_rounded),
  personal('personal', Icons.content_cut_rounded),
  homeServices('home_services', Icons.handyman_rounded),
  health('health', Icons.local_hospital_rounded),
  education('education', Icons.school_rounded),
  leisure('leisure', Icons.beach_access_rounded),
  logistics('logistics', Icons.local_shipping_rounded),
  professional('professional', Icons.business_center_rounded),
  itMedia('it_media', Icons.computer_rounded),
  other('other', Icons.category_rounded);

  const BusinessCategory(this.wire, this.icon);

  /// Серверга юбориладиган/Firestore'да сақланадиган қиймат.
  final String wire;
  final IconData icon;

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
