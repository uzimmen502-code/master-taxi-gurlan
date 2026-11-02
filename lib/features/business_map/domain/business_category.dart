import 'package:flutter/material.dart';

/// Тадбиркорлик объекти фаолият тури — 30 та (эга, 2026-11-01: «олдинги 14 та харита категориясини энг янги
/// 30 та харита категорияси билан такомиллаштир»). Тартиб = эга рўйхатидаги рақам (1 … 30).
///
/// Рўйхат `functions/business_directory.js` даги `CATEGORIES` билан БИР ХИЛ бўлиши шарт (сервер ёзувда шу рўйхат
/// бўйича текширади); паритетни `business_domain_test.dart` қулфлайди. Матн калити: `business_cat_<wire>` (3 тилда).
/// Аниқроқ турлар (автокомплит) — `business_subtypes.dart`.
///
/// Эски 14 талик рўйхатдан мос келганлари (`retail`, `manufacturing`, `food`, `logistics`, `auto`, `personal`,
/// `education`, `health`, `professional`, `other`) ўша wire билан қолди; қолган 4 таси [legacyWires] орқали
/// янгисига ўгирилади (эски ҳужжат ва эски APK юборган қиймат — сервер ҳам худди шундай ўгиради).
///
/// [color] — тур ранги: чип ва харитадаги маркер БИР хил ранг; 30 та ранг бир-биридан фарқ қилади (тест қулфлайди).
enum BusinessCategory {
  retail('retail', Icons.storefront_rounded, Color(0xFFF59E0B)),
  manufacturing('manufacturing', Icons.factory_rounded, Color(0xFF92400E)),
  agriculture('agriculture', Icons.agriculture_rounded, Color(0xFF65A30D)),
  food('food', Icons.restaurant_rounded, Color(0xFFEF4444)),
  logistics('logistics', Icons.local_shipping_rounded, Color(0xFF84CC16)),
  auto('auto', Icons.directions_car_filled_rounded, Color(0xFF6366F1)),
  construction('construction', Icons.construction_rounded, Color(0xFFEA580C)),
  realEstate('real_estate', Icons.home_work_rounded, Color(0xFF0F766E)),
  personal('personal', Icons.content_cut_rounded, Color(0xFFEC4899)),
  education('education', Icons.school_rounded, Color(0xFF8B5CF6)),
  health('health', Icons.local_hospital_rounded, Color(0xFF22C55E)),
  it('it', Icons.computer_rounded, Color(0xFF475569)),
  marketing('marketing', Icons.campaign_rounded, Color(0xFFE11D48)),
  finance('finance', Icons.account_balance_rounded, Color(0xFF1D4ED8)),
  professional('professional', Icons.gavel_rounded, Color(0xFF1E3A8A)),
  tourism('tourism', Icons.luggage_rounded, Color(0xFF06B6D4)),
  sport('sport', Icons.sports_soccer_rounded, Color(0xFF0EA5E9)),
  creative('creative', Icons.palette_rounded, Color(0xFFA855F7)),
  family('family', Icons.family_restroom_rounded, Color(0xFFF472B6)),
  animals('animals', Icons.pets_rounded, Color(0xFFB45309)),
  energy('energy', Icons.bolt_rounded, Color(0xFFCA8A04)),
  rental('rental', Icons.key_rounded, Color(0xFF7C3AED)),
  agency('agency', Icons.handshake_rounded, Color(0xFF0891B2)),
  foreignTrade('foreign_trade', Icons.public_rounded, Color(0xFF2563EB)),
  fashion('fashion', Icons.checkroom_rounded, Color(0xFFC026D3)),
  ecology('ecology', Icons.recycling_rounded, Color(0xFF16A34A)),
  security('security', Icons.security_rounded, Color(0xFF374151)),
  businessSupport('business_support', Icons.business_center_rounded, Color(0xFF4F46E5)),
  social('social', Icons.volunteer_activism_rounded, Color(0xFFF97316)),
  other('other', Icons.category_rounded, Color(0xFF9CA3AF));

  const BusinessCategory(this.wire, this.icon, this.color);

  /// Серверга юбориладиган/Firestore'да сақланадиган қиймат.
  final String wire;
  final IconData icon;
  final Color color;

  String get labelKey => 'business_cat_$wire';


  /// Эски 14 талик рўйхатнинг янги рўйхатда йўқ wire'лари → янгиси. Сервердаги `LEGACY_CATEGORIES` билан бир хил.
  static const legacyWires = <String, BusinessCategory>{
    'wholesale': BusinessCategory.retail,
    'home_services': BusinessCategory.personal,
    'leisure': BusinessCategory.sport,
    'it_media': BusinessCategory.it,
  };

  /// Номаълум/бўш қиймат (бузилган ҳужжат) — `other`; эски wire — янгиси. Харита синмайди (26-банд).
  static BusinessCategory fromWire(Object? raw) {
    final s = (raw ?? '').toString().trim();
    for (final c in values) {
      if (c.wire == s) return c;
    }
    return legacyWires[s] ?? BusinessCategory.other;
  }

  static List<String> get wires => [for (final c in values) c.wire];
}
