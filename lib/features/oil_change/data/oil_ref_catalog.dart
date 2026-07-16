import 'oil_l10n.dart';

/// Chevrolet uchun moy ma'lumotnomasi — 50 to'liq sintetik, 20 yarim sintetik, 20 mineral.
/// Har bir mahsulot: haqiqiy rasmiynomi, tasdiqlangan spetsifikatsiyalar.
class OilRefProduct {
  const OilRefProduct({
    required this.brand,
    required this.name,
    required this.country,
    required this.sae,
    required this.api,
    this.acea = '',
    this.dexos = '',
    required this.oilType,
    required this.chevCompat,
    required this.lpgCngCompat,
    required this.intervalKm,
    required this.rating,
  });

  final String brand;
  final String name;
  final String country;
  final String sae;
  final String api;
  final String acea;
  final String dexos;
  final OilRefType oilType;
  /// Chevrolet benzin dvigatellariga moslik (1–5).
  final int chevCompat;
  /// LPG/CNG dvigatellariga moslik (1–5).
  final int lpgCngCompat;
  /// Tavsiya etilgan almashtirish intervali, ming km.
  final String intervalKm;
  /// Umumiy reyting (10 ballik).
  final double rating;
}

enum OilRefType { full, semi, mineral }

/// Chevrolet modeli → tavsiya etilgan moy.
class ChevModelReco {
  const ChevModelReco(this.model, this.recommendation);
  final String model;
  final String recommendation;
}

/// SAE qo'llanma yozuvi (moy qalinligi izohi) — «Мой ҳақида» tabi uchun.
class SaeGuideEntry {
  const SaeGuideEntry({
    required this.sae,
    required this.badge,
    required this.subtitle,
    required this.thickness,
    required this.hotProtect,
    required this.main,
    required this.engines,
    required this.chevy,
    required this.pros,
    required this.cons,
    required this.lpg,
    required this.lpgBad,
  });

  final String sae;
  /// 'ok' | 'hot' | 'warn' | 'old' | 'min' — rang belgisi.
  final String badge;
  final L3 subtitle;
  final L3 thickness;
  final L3 hotProtect;
  final L3 main;
  final L3 engines;
  final L3 chevy;
  final L3 pros;
  final L3 cons;
  final L3 lpg;
  /// LPG/gaz uchun yaroqsiz bo'lsa true (ogohlantirish rangi).
  final bool lpgBad;
}

abstract final class OilRefCatalog {
  // ─── TO'LIQ SINTETIK (50 ta) ───────────────────────────────

  static const fullSynthetic = <OilRefProduct>[
    OilRefProduct(brand: 'Mobil', name: 'Mobil 1™ 5W-30', country: 'AQSh', sae: '5W-30', api: 'SP', acea: 'A5/B5, C2', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.5),
    OilRefProduct(brand: 'Mobil', name: 'Mobil Super™ All-In-One Protection D1 5W-30', country: 'AQSh', sae: '5W-30', api: 'SP', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'Shell', name: 'Helix Ultra SP 5W-30', country: 'UK/Gollandiya', sae: '5W-30', api: 'SP', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.5),
    OilRefProduct(brand: 'Liqui Moly', name: 'Special Tec DX1 5W-30', country: 'Germaniya', sae: '5W-30', api: 'SP', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.5),
    OilRefProduct(brand: 'Castrol', name: 'EDGE 5W-30', country: 'UK', sae: '5W-30', api: 'SP', acea: 'A5/B5, C2', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.5),
    OilRefProduct(brand: 'Motul', name: '8100 ECO-LITE 5W-30', country: 'Frantsiya', sae: '5W-30', api: 'SP-RC', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.5),
    OilRefProduct(brand: 'TotalEnergies', name: 'Quartz 9000 Future FGC 5W-30', country: 'Frantsiya', sae: '5W-30', api: 'SP', acea: 'GF-6A', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'Ravenol', name: 'HDX 5W-30', country: 'Germaniya', sae: '5W-30', api: 'SP', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'Valvoline', name: 'SynPower DX1 5W-30', country: 'AQSh', sae: '5W-30', api: 'SP', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'Valvoline', name: 'Advanced Full Synthetic 5W-30', country: 'AQSh', sae: '5W-30', api: 'SP/SQ', acea: 'GF-7A', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'ZIC', name: 'X7 D1 5W-30', country: 'Janubiy Koreya', sae: '5W-30', api: 'SP', acea: 'GF-6A', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'ELF', name: 'Evolution 900 USX 5W-30', country: 'Frantsiya', sae: '5W-30', api: 'SP', acea: 'GF-6A', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'Mannol', name: 'Energy Premium 5W-30', country: 'Germaniya', sae: '5W-30', api: 'SP', acea: 'C2, C3', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 8.5),
    OilRefProduct(brand: 'Mannol', name: 'For Chinese Cars 5W-30', country: 'Germaniya', sae: '5W-30', api: 'SP', acea: 'GF-6A', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 8.5),
    OilRefProduct(brand: 'Wolf', name: 'EcoTech 5W-30 SP/RC D1-3', country: 'Belgiya', sae: '5W-30', api: 'SP/RC', acea: 'GF-6A', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'Fuchs', name: 'TITAN Supersyn D1 5W-30', country: 'Germaniya', sae: '5W-30', api: 'SP RC', acea: 'GF-6A', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'Eurol', name: 'Cleantec DXS 5W-30', country: 'Gollandiya', sae: '5W-30', api: 'SP (RC)', acea: 'GF-6A', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'Eni', name: 'i-Sint tech GMX 5W-30', country: 'Italiya', sae: '5W-30', api: 'SP RC', acea: 'GF-6A', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'Petronas', name: 'Syntium 3000 XS 5W-30', country: 'Malayziya', sae: '5W-30', api: 'SP', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 8.5),
    OilRefProduct(brand: 'Kixx', name: 'G1 Dexos1 5W-30', country: 'Janubiy Koreya', sae: '5W-30', api: 'SP', acea: 'GF-6A', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 8.5),
    // Dexos2 (dizel mos) — Chevrolet benzin uchun 4/5
    OilRefProduct(brand: 'Mobil', name: 'Mobil 1 ESP 5W-30', country: 'AQSh', sae: '5W-30', api: 'SP', acea: 'C3', dexos: 'Dexos2', oilType: OilRefType.full, chevCompat: 4, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'Shell', name: 'Helix Ultra ECT C3 5W-30', country: 'UK/Gollandiya', sae: '5W-30', api: 'SP', acea: 'C3', dexos: 'Dexos2', oilType: OilRefType.full, chevCompat: 4, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'Liqui Moly', name: 'Top Tec 4200 5W-30', country: 'Germaniya', sae: '5W-30', api: 'SP', acea: 'C3', dexos: 'Dexos2', oilType: OilRefType.full, chevCompat: 4, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'Castrol', name: 'EDGE C3 5W-30', country: 'UK', sae: '5W-30', api: 'SP', acea: 'C3', dexos: 'Dexos2', oilType: OilRefType.full, chevCompat: 4, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'Motul', name: '8100 X-clean 5W-30', country: 'Frantsiya', sae: '5W-30', api: 'SP', acea: 'C3', dexos: 'Dexos2', oilType: OilRefType.full, chevCompat: 4, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'TotalEnergies', name: 'Quartz INEO MC3 5W-30', country: 'Frantsiya', sae: '5W-30', api: 'SP', acea: 'C3', dexos: 'Dexos2', oilType: OilRefType.full, chevCompat: 4, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'Ravenol', name: 'VMO 5W-30', country: 'Germaniya', sae: '5W-30', api: 'SP', acea: 'C3', dexos: 'Dexos2', oilType: OilRefType.full, chevCompat: 4, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'Valvoline', name: 'SynPower C3 5W-30', country: 'AQSh', sae: '5W-30', api: 'SP', acea: 'C3', dexos: 'Dexos2', oilType: OilRefType.full, chevCompat: 4, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'ZIC', name: 'X9 5W-30', country: 'Janubiy Koreya', sae: '5W-30', api: 'SP', acea: 'C3', dexos: 'Dexos2', oilType: OilRefType.full, chevCompat: 4, lpgCngCompat: 5, intervalKm: '10–15', rating: 8.5),
    OilRefProduct(brand: 'ELF', name: 'Evolution 900 SXR 5W-30', country: 'Frantsiya', sae: '5W-30', api: 'SP', acea: 'C3', dexos: 'Dexos2', oilType: OilRefType.full, chevCompat: 4, lpgCngCompat: 5, intervalKm: '10–15', rating: 8.5),
    // Qo'shimcha Dexos1 Gen3
    OilRefProduct(brand: 'Mobil', name: 'Mobil Super™ Synthetic 5W-30', country: 'AQSh', sae: '5W-30', api: 'SP', acea: 'GF-6A', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'Shell', name: 'Helix Ultra Professional AF 5W-30', country: 'UK/Gollandiya', sae: '5W-30', api: 'SP', acea: 'GF-6A', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'Liqui Moly', name: 'Molygen New Generation 5W-30', country: 'Germaniya', sae: '5W-30', api: 'SP', acea: 'GF-6A', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'Castrol', name: 'MAGNATEC 5W-30 DX', country: 'UK', sae: '5W-30', api: 'SP', acea: 'GF-6A', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'Motul', name: '8100 Eco-energy 5W-30', country: 'Frantsiya', sae: '5W-30', api: 'SP', acea: 'GF-6A', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'TotalEnergies', name: 'Quartz 9000 Energy 5W-30', country: 'Frantsiya', sae: '5W-30', api: 'SP', acea: 'GF-6A', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'Ravenol', name: 'ECS 5W-30', country: 'Germaniya', sae: '5W-30', api: 'SP', acea: 'GF-6A', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'Valvoline', name: 'Extended Protection 5W-30', country: 'AQSh', sae: '5W-30', api: 'SP/SQ', acea: 'GF-7A', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'ZIC', name: 'X5 5W-30', country: 'Janubiy Koreya', sae: '5W-30', api: 'SP', acea: 'GF-6A', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 8.5),
    OilRefProduct(brand: 'ELF', name: 'Evolution 900 FT 5W-30', country: 'Frantsiya', sae: '5W-30', api: 'SP', acea: 'GF-6A', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 8.5),
    OilRefProduct(brand: 'Mannol', name: 'Energy Formula JP 5W-30', country: 'Germaniya', sae: '5W-30', api: 'SP-RC', acea: 'GF-6A', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 8.5),
    OilRefProduct(brand: 'Wolf', name: 'OfficialTech 5W-30 C3', country: 'Belgiya', sae: '5W-30', api: 'SP', acea: 'C3', dexos: 'Dexos2', oilType: OilRefType.full, chevCompat: 4, lpgCngCompat: 5, intervalKm: '10–15', rating: 8.5),
    OilRefProduct(brand: 'Fuchs', name: 'TITAN GT1 5W-30 C3', country: 'Germaniya', sae: '5W-30', api: 'SP', acea: 'C3', dexos: 'Dexos2', oilType: OilRefType.full, chevCompat: 4, lpgCngCompat: 5, intervalKm: '10–15', rating: 9.0),
    OilRefProduct(brand: 'Eurol', name: 'Syntence 5W-30', country: 'Gollandiya', sae: '5W-30', api: 'SP', acea: 'C3', dexos: 'Dexos2', oilType: OilRefType.full, chevCompat: 4, lpgCngCompat: 5, intervalKm: '10–15', rating: 8.5),
    OilRefProduct(brand: 'Eni', name: 'i-Sint 5W-30', country: 'Italiya', sae: '5W-30', api: 'SP', acea: 'C3', dexos: 'Dexos2', oilType: OilRefType.full, chevCompat: 4, lpgCngCompat: 5, intervalKm: '10–15', rating: 8.5),
    OilRefProduct(brand: 'Petronas', name: 'Syntium 7000 5W-30', country: 'Malayziya', sae: '5W-30', api: 'SP', acea: 'C3', dexos: 'Dexos2', oilType: OilRefType.full, chevCompat: 4, lpgCngCompat: 5, intervalKm: '10–15', rating: 8.5),
    OilRefProduct(brand: 'Kixx', name: 'G1 5W-30 C3', country: 'Janubiy Koreya', sae: '5W-30', api: 'SP', acea: 'C3', dexos: 'Dexos2', oilType: OilRefType.full, chevCompat: 4, lpgCngCompat: 5, intervalKm: '10–15', rating: 8.5),
    OilRefProduct(brand: 'Idemitsu', name: 'Fully Synthetic 5W-30 SP', country: 'Yaponiya', sae: '5W-30', api: 'SP', acea: 'GF-6A', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 8.5),
    OilRefProduct(brand: 'Q8', name: 'Formula Special G Long Life 5W-30', country: 'Quvayt', sae: '5W-30', api: 'SP', acea: 'GF-6A', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 8.5),
    OilRefProduct(brand: 'Repsol', name: 'Elite Long Life 5W-30', country: 'Ispaniya', sae: '5W-30', api: 'SP', acea: 'GF-6A', dexos: 'Dexos1 Gen 3', oilType: OilRefType.full, chevCompat: 5, lpgCngCompat: 5, intervalKm: '10–15', rating: 8.5),
  ];

  // ─── YARIM SINTETIK (20 ta) — haqiqiy mahsulot nomlari ─────

  static const semiSynthetic = <OilRefProduct>[
    OilRefProduct(brand: 'Mobil', name: 'Super 2000 X1 10W-40', country: 'AQSh', sae: '10W-40', api: 'SN Plus', acea: 'A3/B4', oilType: OilRefType.semi, chevCompat: 4, lpgCngCompat: 4, intervalKm: '7–10', rating: 8.5),
    OilRefProduct(brand: 'Shell', name: 'Helix HX7 10W-40', country: 'UK/Gollandiya', sae: '10W-40', api: 'SN Plus', acea: 'A3/B4', oilType: OilRefType.semi, chevCompat: 4, lpgCngCompat: 4, intervalKm: '7–10', rating: 8.5),
    OilRefProduct(brand: 'Liqui Moly', name: 'Optimal 10W-40', country: 'Germaniya', sae: '10W-40', api: 'SL/CF', acea: 'A3/B4', oilType: OilRefType.semi, chevCompat: 4, lpgCngCompat: 4, intervalKm: '7–10', rating: 8.5),
    OilRefProduct(brand: 'Castrol', name: 'MAGNATEC 10W-40 A3/B4', country: 'UK', sae: '10W-40', api: 'SN', acea: 'A3/B4', oilType: OilRefType.semi, chevCompat: 4, lpgCngCompat: 4, intervalKm: '7–10', rating: 8.5),
    OilRefProduct(brand: 'Motul', name: '6100 Synergie+ 10W-40', country: 'Frantsiya', sae: '10W-40', api: 'SN', acea: 'A3/B4', oilType: OilRefType.semi, chevCompat: 4, lpgCngCompat: 4, intervalKm: '7–10', rating: 8.5),
    OilRefProduct(brand: 'TotalEnergies', name: 'Quartz 7000 10W-40', country: 'Frantsiya', sae: '10W-40', api: 'SN', acea: 'A3/B4', oilType: OilRefType.semi, chevCompat: 4, lpgCngCompat: 4, intervalKm: '7–10', rating: 8.5),
    OilRefProduct(brand: 'Ravenol', name: 'TSI 10W-40', country: 'Germaniya', sae: '10W-40', api: 'SN', acea: 'A3/B4', oilType: OilRefType.semi, chevCompat: 4, lpgCngCompat: 4, intervalKm: '7–10', rating: 8.5),
    OilRefProduct(brand: 'Valvoline', name: 'MaxLife 10W-40', country: 'AQSh', sae: '10W-40', api: 'SN', acea: 'A3/B4', oilType: OilRefType.semi, chevCompat: 4, lpgCngCompat: 4, intervalKm: '7–10', rating: 8.5),
    OilRefProduct(brand: 'ELF', name: 'Evolution 700 STI 10W-40', country: 'Frantsiya', sae: '10W-40', api: 'SN', acea: 'A3/B4', oilType: OilRefType.semi, chevCompat: 4, lpgCngCompat: 4, intervalKm: '7–10', rating: 8.5),
    OilRefProduct(brand: 'ZIC', name: 'X5 10W-40', country: 'Janubiy Koreya', sae: '10W-40', api: 'SN Plus', acea: 'A3/B4', oilType: OilRefType.semi, chevCompat: 4, lpgCngCompat: 4, intervalKm: '7–10', rating: 8.5),
    OilRefProduct(brand: 'Mannol', name: 'Classic 10W-40', country: 'Germaniya', sae: '10W-40', api: 'SN/CF', acea: 'A3/B4', oilType: OilRefType.semi, chevCompat: 4, lpgCngCompat: 4, intervalKm: '7–10', rating: 8.0),
    OilRefProduct(brand: 'Fuchs', name: 'TITAN SYN MC 10W-40', country: 'Germaniya', sae: '10W-40', api: 'SN', acea: 'A3/B4', oilType: OilRefType.semi, chevCompat: 4, lpgCngCompat: 4, intervalKm: '7–10', rating: 8.5),
    OilRefProduct(brand: 'Wolf', name: 'GuardTech B4 10W-40', country: 'Belgiya', sae: '10W-40', api: 'SN', acea: 'A3/B4', oilType: OilRefType.semi, chevCompat: 4, lpgCngCompat: 4, intervalKm: '7–10', rating: 8.0),
    OilRefProduct(brand: 'Eni', name: 'i-Sint Professional 10W-40', country: 'Italiya', sae: '10W-40', api: 'SN', acea: 'A3/B4', oilType: OilRefType.semi, chevCompat: 4, lpgCngCompat: 4, intervalKm: '7–10', rating: 8.0),
    OilRefProduct(brand: 'Petronas', name: 'Syntium 800 10W-40', country: 'Malayziya', sae: '10W-40', api: 'SN', acea: 'A3/B4', oilType: OilRefType.semi, chevCompat: 4, lpgCngCompat: 4, intervalKm: '7–10', rating: 8.0),
    OilRefProduct(brand: 'Kixx', name: 'Gold SN 10W-40', country: 'Janubiy Koreya', sae: '10W-40', api: 'SN', acea: 'A3/B4', oilType: OilRefType.semi, chevCompat: 4, lpgCngCompat: 4, intervalKm: '7–10', rating: 8.0),
    OilRefProduct(brand: 'Castrol', name: 'GTX Ultraclean 10W-40 A3/B4', country: 'UK', sae: '10W-40', api: 'SN', acea: 'A3/B4', oilType: OilRefType.semi, chevCompat: 4, lpgCngCompat: 4, intervalKm: '7–10', rating: 8.5),
    OilRefProduct(brand: 'Shell', name: 'Helix HX6 10W-40', country: 'UK/Gollandiya', sae: '10W-40', api: 'SN', acea: 'A3/B3', oilType: OilRefType.semi, chevCompat: 4, lpgCngCompat: 3, intervalKm: '7–10', rating: 8.0),
    OilRefProduct(brand: 'Liqui Moly', name: 'Super Leichtlauf 10W-40', country: 'Germaniya', sae: '10W-40', api: 'SN/CF', acea: 'A3/B4', oilType: OilRefType.semi, chevCompat: 4, lpgCngCompat: 4, intervalKm: '7–10', rating: 8.5),
    OilRefProduct(brand: 'Motul', name: '4100 Turbolight 10W-40', country: 'Frantsiya', sae: '10W-40', api: 'SN', acea: 'A3/B4', oilType: OilRefType.semi, chevCompat: 4, lpgCngCompat: 4, intervalKm: '7–10', rating: 8.5),
  ];

  // ─── MINERAL (20 ta) — haqiqiy mahsulot nomlari ────────────

  static const mineral = <OilRefProduct>[
    OilRefProduct(brand: 'Mobil', name: 'Super 1000 X1 15W-40', country: 'AQSh', sae: '15W-40', api: 'SL/CF', acea: 'A3/B3', oilType: OilRefType.mineral, chevCompat: 3, lpgCngCompat: 3, intervalKm: '5–7', rating: 7.5),
    OilRefProduct(brand: 'Shell', name: 'Helix HX3 15W-40', country: 'UK/Gollandiya', sae: '15W-40', api: 'SL/CF', acea: 'A3/B3', oilType: OilRefType.mineral, chevCompat: 3, lpgCngCompat: 3, intervalKm: '5–7', rating: 7.5),
    OilRefProduct(brand: 'Liqui Moly', name: 'MoS2 Leichtlauf 15W-40', country: 'Germaniya', sae: '15W-40', api: 'SL/CF', acea: 'A3/B4', oilType: OilRefType.mineral, chevCompat: 3, lpgCngCompat: 3, intervalKm: '5–7', rating: 7.5),
    OilRefProduct(brand: 'Castrol', name: 'GTX 15W-40 A3/B3', country: 'UK', sae: '15W-40', api: 'SL', acea: 'A3/B3', oilType: OilRefType.mineral, chevCompat: 3, lpgCngCompat: 3, intervalKm: '5–7', rating: 7.5),
    OilRefProduct(brand: 'Motul', name: '2100 Power+ 15W-40', country: 'Frantsiya', sae: '15W-40', api: 'SL', acea: 'A3/B3', oilType: OilRefType.mineral, chevCompat: 3, lpgCngCompat: 3, intervalKm: '5–7', rating: 7.5),
    OilRefProduct(brand: 'TotalEnergies', name: 'Quartz 5000 15W-40', country: 'Frantsiya', sae: '15W-40', api: 'SL/CF', acea: 'A3/B3', oilType: OilRefType.mineral, chevCompat: 3, lpgCngCompat: 3, intervalKm: '5–7', rating: 7.5),
    OilRefProduct(brand: 'Ravenol', name: 'Formel Standard 15W-40', country: 'Germaniya', sae: '15W-40', api: 'SF/CD', acea: 'A3/B3', oilType: OilRefType.mineral, chevCompat: 3, lpgCngCompat: 3, intervalKm: '5–7', rating: 7.0),
    OilRefProduct(brand: 'Valvoline', name: 'Daily Protection 15W-40', country: 'AQSh', sae: '15W-40', api: 'SN', acea: 'A3/B3', oilType: OilRefType.mineral, chevCompat: 3, lpgCngCompat: 3, intervalKm: '5–7', rating: 7.5),
    OilRefProduct(brand: 'ELF', name: 'Evolution 500 TS 15W-40', country: 'Frantsiya', sae: '15W-40', api: 'SL/CF', acea: 'A3/B3', oilType: OilRefType.mineral, chevCompat: 3, lpgCngCompat: 3, intervalKm: '5–7', rating: 7.5),
    OilRefProduct(brand: 'ZIC', name: 'X5 15W-40', country: 'Janubiy Koreya', sae: '15W-40', api: 'SL/CF', acea: 'A3/B3', oilType: OilRefType.mineral, chevCompat: 3, lpgCngCompat: 3, intervalKm: '5–7', rating: 7.5),
    OilRefProduct(brand: 'Mannol', name: 'Universal 15W-40', country: 'Germaniya', sae: '15W-40', api: 'SG/CD', acea: 'A3/B3', oilType: OilRefType.mineral, chevCompat: 3, lpgCngCompat: 3, intervalKm: '5–7', rating: 7.0),
    OilRefProduct(brand: 'Wolf', name: 'GuardTech B4 15W-40', country: 'Belgiya', sae: '15W-40', api: 'SL/CF', acea: 'A3/B4', oilType: OilRefType.mineral, chevCompat: 3, lpgCngCompat: 3, intervalKm: '5–7', rating: 7.0),
    OilRefProduct(brand: 'Fuchs', name: 'TITAN Universal HD 15W-40', country: 'Germaniya', sae: '15W-40', api: 'SL/CF', acea: 'A3/B3', oilType: OilRefType.mineral, chevCompat: 3, lpgCngCompat: 3, intervalKm: '5–7', rating: 7.5),
    OilRefProduct(brand: 'Eni', name: 'i-Sigma Universal 15W-40', country: 'Italiya', sae: '15W-40', api: 'SL/CF', acea: 'A3/B3', oilType: OilRefType.mineral, chevCompat: 3, lpgCngCompat: 3, intervalKm: '5–7', rating: 7.0),
    OilRefProduct(brand: 'Petronas', name: 'Mach 5 15W-40', country: 'Malayziya', sae: '15W-40', api: 'SL/CF', acea: 'A3/B3', oilType: OilRefType.mineral, chevCompat: 3, lpgCngCompat: 3, intervalKm: '5–7', rating: 7.0),
    OilRefProduct(brand: 'Kixx', name: 'HD 15W-40', country: 'Janubiy Koreya', sae: '15W-40', api: 'SL/CF', acea: 'A3/B3', oilType: OilRefType.mineral, chevCompat: 3, lpgCngCompat: 3, intervalKm: '5–7', rating: 7.0),
    OilRefProduct(brand: 'Repsol', name: 'Elite Multivalvulas 15W-40', country: 'Ispaniya', sae: '15W-40', api: 'SN', acea: 'A3/B4', oilType: OilRefType.mineral, chevCompat: 3, lpgCngCompat: 3, intervalKm: '5–7', rating: 7.5),
    OilRefProduct(brand: 'Idemitsu', name: 'SN/CF 15W-40', country: 'Yaponiya', sae: '15W-40', api: 'SN/CF', acea: 'A3/B3', oilType: OilRefType.mineral, chevCompat: 3, lpgCngCompat: 3, intervalKm: '5–7', rating: 7.0),
    OilRefProduct(brand: 'Eurol', name: 'Turbosyn 15W-40', country: 'Gollandiya', sae: '15W-40', api: 'SL/CF', acea: 'A3/B4', oilType: OilRefType.mineral, chevCompat: 3, lpgCngCompat: 3, intervalKm: '5–7', rating: 7.0),
    OilRefProduct(brand: 'Q8', name: 'T 800 15W-40', country: 'Quvayt', sae: '15W-40', api: 'SL/CF', acea: 'A3/B3', oilType: OilRefType.mineral, chevCompat: 3, lpgCngCompat: 3, intervalKm: '5–7', rating: 7.0),
  ];

  // ─── BARCHA MAHSULOTLAR ────────────────────────────────────

  static List<OilRefProduct> get all => [
        ...fullSynthetic,
        ...semiSynthetic,
        ...mineral,
      ];

  // ─── MODEL BO'YICHA TAVSIYALAR ─────────────────────────────

  static const modelRecos = <ChevModelReco>[
    ChevModelReco('Damas', '10W-40 Yarim sintetik yoki 15W-40 Mineral'),
    ChevModelReco('Matiz', '10W-40 Yarim sintetik yoki 5W-30 Sintetik'),
    ChevModelReco('Nexia 1', '10W-40 Yarim sintetik yoki 5W-30 Sintetik'),
    ChevModelReco('Nexia 2', '5W-30 Sintetik yoki 10W-40 Yarim sintetik'),
    ChevModelReco('Nexia 3', '5W-30 Full Synthetic (Dexos1 Gen2/Gen3)'),
    ChevModelReco('Spark', '5W-30 Full Synthetic (Dexos1 Gen2/Gen3)'),
    ChevModelReco('Cobalt', '5W-30 Full Synthetic (Dexos1 Gen2/Gen3)'),
    ChevModelReco('Gentra', '5W-30 Full Synthetic (Dexos1 Gen2/Gen3)'),
    ChevModelReco('Lacetti', '5W-30 Full Synthetic (Dexos1 Gen2/Gen3)'),
    ChevModelReco('Malibu', '5W-30 Full Synthetic (Dexos1 Gen2/Gen3)'),
    ChevModelReco('Tracker', '5W-30 Full Synthetic (Dexos1 Gen2/Gen3)'),
  ];

  // ─── SAE QO'LLANMA (Мой ҳақида tabi) ───────────────────────
  // Tartib HTML bilan bir xil: 5W-30 birinchi (default ochiq).

  static const saeGuide = <SaeGuideEntry>[
    SaeGuideEntry(
      sae: '5W-30',
      badge: 'ok',
      subtitle: L3(
        'Универсал «Олтин стандарт» · завод тавсияси',
        'Universal «Oltin standart» · zavod tavsiyasi',
        'Универсальный «золотой стандарт» · заводская рекомендация',
      ),
      thickness: L3(
        'Ўртача суюқ. Қишда −30°C гача ишонади, ёзги иссиқда (40°C) яхши ҳимоя қилади.',
        'O‘rtacha suyuq. Qishda −30°C gacha ishonadi, yozgi issiqda (40°C) yaxshi himoya qiladi.',
        'Средней текучести. Зимой уверенно работает до −30°C, в летнюю жару (40°C) хорошо защищает.',
      ),
      hotProtect: L3(
        '100°C да ёпишқоқлиги 9.3–12.5 cSt. Аксарият двигателлар учун «шифт» ҳисобланади.',
        '100°C da yopishqoqligi 9.3–12.5 cSt. Aksariyat dvigatellar uchun «shift» hisoblanadi.',
        'При 100°C вязкость 9.3–12.5 cSt. Для большинства двигателей — «эталон».',
      ),
      main: L3(
        'Энергия тежамкорлиги ва ҳимоя ўртасидаги мукаммал мувозанат.',
        'Energiya tejamkorligi va himoya o‘rtasidagi mukammal muvozanat.',
        'Идеальный баланс между экономией энергии и защитой.',
      ),
      engines: L3(
        '0–150 000 км юргизишли барча замонавий бензин двигателлари.',
        '0–150 000 km yurgizishli barcha zamonaviy benzin dvigatellari.',
        'Все современные бензиновые двигатели с пробегом 0–150 000 км.',
      ),
      chevy: L3(
        'Chevrolet заводи томонидан расмий тавсия этилган асосий вязкость. Cobalt, Gentra, Nexia, Lacetti, Spark, Malibu (бензин) учун 1-рақамли танлов.',
        'Chevrolet zavodi tomonidan rasmiy tavsiya etilgan asosiy yopishqoqlik. Cobalt, Gentra, Nexia, Lacetti, Spark, Malibu (benzin) uchun 1-raqamli tanlov.',
        'Основная вязкость, официально рекомендованная заводом Chevrolet. Для Cobalt, Gentra, Nexia, Lacetti, Spark, Malibu (бензин) — выбор №1.',
      ),
      pros: L3(
        'Универсал, ҳарорат ўзгаришига чидамли, Dexos1 Gen3 билан келганда 15 000 км гача ишлайди. LPG да ҳам ўртача даражада ишлайди (агар C3 бўлмаса).',
        'Universal, harorat o‘zgarishiga chidamli, Dexos1 Gen3 bilan kelganda 15 000 km gacha ishlaydi. LPG da ham o‘rtacha darajada ishlaydi (agar C3 bo‘lmasa).',
        'Универсальное, устойчиво к перепадам температур, с допуском Dexos1 Gen3 работает до 15 000 км. На LPG работает средне (если это не C3).',
      ),
      cons: L3(
        'Юқори юкланган турбо двигателлар ва иссиқ иқлимда 5W-40 га нисбатан ҳимояси паст.',
        'Yuqori yuklangan turbo dvigatellar va issiq iqlimda 5W-40 ga nisbatan himoyasi past.',
        'В сильно нагруженных турбодвигателях и жарком климате защита ниже, чем у 5W-40.',
      ),
      lpg: L3(
        'Тўлиқ синтетик ва Dexos1 Gen3 бўлса, LPG учун яроқли, лекин 10 000 км дан оширмаслик керак. Агар ACEA C3 (Dexos2) бўлса, LPG учун жуда яхши.',
        'To‘liq sintetik va Dexos1 Gen3 bo‘lsa, LPG uchun yaroqli, lekin 10 000 km dan oshirmaslik kerak. Agar ACEA C3 (Dexos2) bo‘lsa, LPG uchun juda yaxshi.',
        'Если полная синтетика и Dexos1 Gen3 — подходит для LPG, но не более 10 000 км. Если ACEA C3 (Dexos2) — для LPG отлично.',
      ),
      lpgBad: false,
    ),
    SaeGuideEntry(
      sae: '5W-40',
      badge: 'hot',
      subtitle: L3(
        'Иссиққа чидамли · «Европа» стандарти',
        'Issiqqa chidamli · «Yevropa» standarti',
        'Жаростойкое · «европейский» стандарт',
      ),
      thickness: L3(
        '5W-30 га нисбатан қалинроқ. Совуқда ҳам суюқ, лекин иссиқда (100°C) ёпишқоқлиги 12.5–16.3 cSt.',
        '5W-30 ga nisbatan qalinroq. Sovuqda ham suyuq, lekin issiqda (100°C) yopishqoqligi 12.5–16.3 cSt.',
        'Гуще, чем 5W-30. На холоде тоже текучее, но в жару (100°C) вязкость 12.5–16.3 cSt.',
      ),
      hotProtect: L3(
        'Юқори ҳароратдаги ҳимоя (HTHS) — 3.5 дан юқори. Мой плёнкаси жуда мустаҳкам.',
        'Yuqori haroratdagi himoya (HTHS) — 3.5 dan yuqori. Moy plyonkasi juda mustahkam.',
        'Защита при высокой температуре (HTHS) — выше 3.5. Масляная плёнка очень прочная.',
      ),
      main: L3(
        '150–250 000 км, турбонаддувли ёки иссиқ иқлимда ишлайдиган двигателлар учун.',
        '150–250 000 km, turbonadduvli yoki issiq iqlimda ishlaydigan dvigatellar uchun.',
        'Для двигателей 150–250 000 км, турбированных или работающих в жарком климате.',
      ),
      engines: L3(
        '150–250 000 км юргизишли, турбонаддувли, ёки иссиқ иқлимда ишлайдиган двигателлар.',
        '150–250 000 km yurgizishli, turbonadduvli, yoki issiq iqlimda ishlaydigan dvigatellar.',
        'Двигатели с пробегом 150–250 000 км, турбированные или работающие в жарком климате.',
      ),
      chevy: L3(
        'Cobalt/Gentra 150 000 км дан ошганда 5W-30 дан 5W-40 га ўтиш энг тўғри стратегия. Tracker турбо учун иссиқ ҳудудларда ҳам қўйиш мумкин.',
        'Cobalt/Gentra 150 000 km dan oshganda 5W-30 dan 5W-40 ga o‘tish eng to‘g‘ri strategiya. Tracker turbo uchun issiq hududlarda ham qo‘yish mumkin.',
        'Для Cobalt/Gentra после 150 000 км переход с 5W-30 на 5W-40 — верная стратегия. Для турбо Tracker можно и в жарких регионах.',
      ),
      pros: L3(
        'Мойни камайтирмайди (сарфламайди), поршен-цилиндр оралиғи каттайганда ҳам босимни ушлаб туради.',
        'Moyni kamaytirmaydi (sarflamaydi), porshen-tsilindr oralig‘i kattayganda ham bosimni ushlab turadi.',
        'Не расходует масло, держит давление даже при увеличенном зазоре поршень-цилиндр.',
      ),
      cons: L3(
        '5W-30 га нисбатан бензин сарфи 2–3% га ошади. Совуқда (−20°C) бироз оғир ишга тушади.',
        '5W-30 ga nisbatan benzin sarfi 2–3% ga oshadi. Sovuqda (−20°C) biroz og‘ir ishga tushadi.',
        'По сравнению с 5W-30 расход бензина выше на 2–3%. На холоде (−20°C) пуск чуть тяжелее.',
      ),
      lpg: L3(
        'Энг яхши вариантлардан бири. ACEA A3/B4 ёки C3 (Dexos2) билан келса, газ юқори ҳароратида клапанларни ажойиб ҳимоя қилади.',
        'Eng yaxshi variantlardan biri. ACEA A3/B4 yoki C3 (Dexos2) bilan kelsa, gaz yuqori haroratida klapanlarni ajoyib himoya qiladi.',
        'Один из лучших вариантов. С допуском ACEA A3/B4 или C3 (Dexos2) отлично защищает клапаны при высокой температуре газа.',
      ),
      lpgBad: false,
    ),
    SaeGuideEntry(
      sae: '0W-20',
      badge: 'warn',
      subtitle: L3(
        'Энг суюқ · замонавий стандарт',
        'Eng suyuq · zamonaviy standart',
        'Самое текучее · современный стандарт',
      ),
      thickness: L3(
        'Жуда суюқ. Совуқда (−35°C гача) энг яхши оқувчанлик.',
        'Juda suyuq. Sovuqda (−35°C gacha) eng yaxshi oquvchanlik.',
        'Очень текучее. На холоде (до −35°C) наилучшая прокачиваемость.',
      ),
      hotProtect: L3(
        '100°C да ёпишқоқлиги 6.9–9.3 cSt (керакли минимум).',
        '100°C da yopishqoqligi 6.9–9.3 cSt (kerakli minimum).',
        'При 100°C вязкость 6.9–9.3 cSt (необходимый минимум).',
      ),
      main: L3(
        'Максимал ёнилғи тежамкорлиги (Fuel Economy). Ишқаланишни минимумга туширади.',
        'Maksimal yonilg‘i tejamkorligi (Fuel Economy). Ishqalanishni minimumga tushiradi.',
        'Максимальная топливная экономичность (Fuel Economy). Сводит трение к минимуму.',
      ),
      engines: L3(
        'Фақат 2010 йилдан кейинги, жуда аниқ геометрияли, турбонаддувсиз ёки гибрид двигателлар.',
        'Faqat 2010 yildan keyingi, juda aniq geometriyali, turbonadduvsiz yoki gibrid dvigatellar.',
        'Только двигатели после 2010 года с очень точной геометрией, без турбонаддува или гибридные.',
      ),
      chevy: L3(
        'Cobalt/Gentra 1.5 ёки Tracker учун фақат Dexos1 Gen3 тасдиғи билан ишлатиш мумкин.',
        'Cobalt/Gentra 1.5 yoki Tracker uchun faqat Dexos1 Gen3 tasdig‘i bilan ishlatish mumkin.',
        'Для Cobalt/Gentra 1.5 или Tracker можно использовать только с допуском Dexos1 Gen3.',
      ),
      pros: L3(
        'Совуқ ишга тушиш осон, бензин тежалади, кул ва лой қолдиқлари жуда кам.',
        'Sovuq ishga tushish oson, benzin tejaladi, kul va loy qoldiqlari juda kam.',
        'Лёгкий холодный пуск, экономия бензина, очень мало золы и отложений.',
      ),
      cons: L3(
        'Эски ва иссиқда яхши совутмайдиган двигателларда металл-металл уринишига олиб келиши мумкин. 150 000 км дан ошган моторга қўйиш мумкин эмас.',
        'Eski va issiqda yaxshi sovutmaydigan dvigatellarda metall-metall urinishiga olib kelishi mumkin. 150 000 km dan oshgan motorga qo‘yish mumkin emas.',
        'В старых и плохо охлаждаемых двигателях может привести к контакту «металл-металл». Нельзя лить в мотор с пробегом свыше 150 000 км.',
      ),
      lpg: L3(
        'Мутлақо мос эмас (газ юқори ҳарорат беради, мой жуда суюқ бўлиб, поршен эришишига сабаб бўлади).',
        'Mutlaqo mos emas (gaz yuqori harorat beradi, moy juda suyuq bo‘lib, porshen erishishiga sabab bo‘ladi).',
        'Совершенно не подходит (газ даёт высокую температуру, слишком текучее масло приводит к задирам поршня).',
      ),
      lpgBad: true,
    ),
    SaeGuideEntry(
      sae: '10W-40',
      badge: 'old',
      subtitle: L3(
        'Ярим синтетик · эски двигателлар',
        'Yarim sintetik · eski dvigatellar',
        'Полусинтетика · старые двигатели',
      ),
      thickness: L3(
        '5W-40 га нисбатан совуқда жуда қалин. −20°C гача ишлайди (ундан пастда мушкул).',
        '5W-40 ga nisbatan sovuqda juda qalin. −20°C gacha ishlaydi (undan pastda mushkul).',
        'На холоде гораздо гуще, чем 5W-40. Работает до −20°C (ниже — трудно).',
      ),
      hotProtect: L3(
        'Эски двигателлардаги босимни тиклаш учун мўлжалланган. Одатда минерал ёки ярим синтетик.',
        'Eski dvigatellardagi bosimni tiklash uchun mo‘ljallangan. Odatda mineral yoki yarim sintetik.',
        'Рассчитано на восстановление давления в старых двигателях. Обычно минеральное или полусинтетика.',
      ),
      main: L3(
        '250 000 км дан ошган, цилиндр-поршен гуруҳи эскирган, мой сарфлайдиган двигателлар.',
        '250 000 km dan oshgan, tsilindr-porshen guruhi eskirgan, moy sarflaydigan dvigatellar.',
        'Двигатели с пробегом свыше 250 000 км, с изношенной цилиндро-поршневой группой, расходующие масло.',
      ),
      engines: L3(
        '250 000 км дан ошган, мой сарфлайдиган двигателлар.',
        '250 000 km dan oshgan, moy sarflaydigan dvigatellar.',
        'Двигатели с пробегом свыше 250 000 км, расходующие масло.',
      ),
      chevy: L3(
        'Фақат эски авлод Nexia 1 / Damas / Matiz учун. Cobalt/Gentra (1.5) га қўйиш тавсия этилмайди — гидрокомпенсаторлар ўз вақтида «тўлдириб» улгурмайди.',
        'Faqat eski avlod Nexia 1 / Damas / Matiz uchun. Cobalt/Gentra (1.5) ga qo‘yish tavsiya etilmaydi — gidrokompensatorlar o‘z vaqtida «to‘ldirib» ulgurmaydi.',
        'Только для старого поколения Nexia 1 / Damas / Matiz. В Cobalt/Gentra (1.5) заливать не рекомендуется — гидрокомпенсаторы не успевают «прокачиваться».',
      ),
      pros: L3(
        'Арзон, эски двигателда босимни яхши ушлайди, мой сарфини камайтиради.',
        'Arzon, eski dvigatelda bosimni yaxshi ushlaydi, moy sarfini kamaytiradi.',
        'Дешёвое, хорошо держит давление в старом двигателе, снижает расход масла.',
      ),
      cons: L3(
        'Бензин тежамкорлиги ёмон (3–5% га ортади). Совуқда двигател жуда оғир айланади. Ресурси 7–8 минг км дан ошмайди.',
        'Benzin tejamkorligi yomon (3–5% ga ortadi). Sovuqda dvigatel juda og‘ir aylanadi. Resursi 7–8 ming km dan oshmaydi.',
        'Плохая топливная экономичность (расход растёт на 3–5%). На холоде двигатель крутится очень тяжело. Ресурс не более 7–8 тыс. км.',
      ),
      lpg: L3(
        'Ярим синтетик бўлгани учун LPG даги юқори ҳароратда тез ёниб кетади. LPG учун яроқсиз (агар махсус газ формуляцияси бўлмаса).',
        'Yarim sintetik bo‘lgani uchun LPG dagi yuqori haroratda tez yonib ketadi. LPG uchun yaroqsiz (agar maxsus gaz formulyatsiyasi bo‘lmasa).',
        'Так как это полусинтетика, быстро выгорает при высокой температуре LPG. Для LPG не годится (если нет специальной газовой формулы).',
      ),
      lpgBad: true,
    ),
    SaeGuideEntry(
      sae: '15W-40',
      badge: 'min',
      subtitle: L3(
        'Минерал · бюджет ва оғир юк',
        'Mineral · byudjet va og‘ir yuk',
        'Минеральное · бюджет и тяжёлая нагрузка',
      ),
      thickness: L3(
        'Энг қалин. Совуқда −15°C гача ишлайди, ундан пастда двигателни айлантириш қийин.',
        'Eng qalin. Sovuqda −15°C gacha ishlaydi, undan pastda dvigatelni aylantirish qiyin.',
        'Самое густое. На холоде работает до −15°C, ниже провернуть двигатель трудно.',
      ),
      hotProtect: L3(
        'Эски технология. Кўпинча минерал асосда. Мой плёнкаси жуда қалин, лекин иссиқда тез суюқланади.',
        'Eski texnologiya. Ko‘pincha mineral asosda. Moy plyonkasi juda qalin, lekin issiqda tez suyuqlanadi.',
        'Старая технология. Чаще на минеральной основе. Масляная плёнка очень толстая, но в жару быстро разжижается.',
      ),
      main: L3(
        'Фақат 300 000+ км босиб ўтган, ёки заводдан 15W-40 талаб қиладиган эски двигателлар.',
        'Faqat 300 000+ km bosib o‘tgan, yoki zavoddan 15W-40 talab qiladigan eski dvigatellar.',
        'Только старые двигатели с пробегом 300 000+ км или те, что с завода требуют 15W-40.',
      ),
      engines: L3(
        '300 000+ км ёки жуда эски / оғир юкли двигателлар.',
        '300 000+ km yoki juda eski / og‘ir yukli dvigatellar.',
        '300 000+ км или очень старые / сильно нагруженные двигатели.',
      ),
      chevy: L3(
        'Фақат эски Nexia / Lacetti да мой сарфлаши жуда кўп бўлганда вақтинчалик. Cobalt / Gentra / Tracker га қатъиян ман.',
        'Faqat eski Nexia / Lacetti da moy sarflashi juda ko‘p bo‘lganda vaqtinchalik. Cobalt / Gentra / Tracker ga qat’iyan man.',
        'Только временно на старых Nexia / Lacetti при очень большом расходе масла. Для Cobalt / Gentra / Tracker строго запрещено.',
      ),
      pros: L3(
        'Жуда арзон. Эски, ширали двигателларда гидрокомпенсатор шовқинини камайтиради (босимни оширади).',
        'Juda arzon. Eski, shirali dvigatellarda gidrokompensator shovqinini kamaytiradi (bosimni oshiradi).',
        'Очень дешёвое. В старых изношенных двигателях снижает шум гидрокомпенсаторов (поднимает давление).',
      ),
      cons: L3(
        'Ёнилғи тежамкорлиги энг ёмон. Қишда ишга тушиш муаммоси. Ресурси 5 000 км. Замонавий катализатор ва фильтрни тезда тиқиб қўяди.',
        'Yonilg‘i tejamkorligi eng yomon. Qishda ishga tushish muammosi. Resursi 5 000 km. Zamonaviy katalizator va filtrni tezda tiqib qo‘yadi.',
        'Худшая топливная экономичность. Проблемы с пуском зимой. Ресурс 5 000 км. Быстро забивает современный катализатор и фильтр.',
      ),
      lpg: L3(
        'Мутлақо яроқсиз. Газ ҳароратида тезда ёниб, коксланиб қолади, поршен халқаларини бикиштириб қўяди.',
        'Mutlaqo yaroqsiz. Gaz haroratida tezda yonib, kokslanib qoladi, porshen halqalarini bikishtirib qo‘yadi.',
        'Совершенно не годится. При температуре газа быстро выгорает и коксуется, залегают поршневые кольца.',
      ),
      lpgBad: true,
    ),
  ];

  /// SAE qiyosiy jadval qatorlari: [ko'rsatkich, 0W-20, 5W-30, 5W-40, 10W-40, 15W-40].
  static const saeCompareRows = <List<L3>>[
    [
      L3('Қишлик чегара', 'Qishki chegara', 'Зимний предел'),
      L3('−35°C', '−35°C', '−35°C'),
      L3('−30°C', '−30°C', '−30°C'),
      L3('−30°C', '−30°C', '−30°C'),
      L3('−20°C', '−20°C', '−20°C'),
      L3('−15°C', '−15°C', '−15°C'),
    ],
    [
      L3('100°C ёпишқоқлик', '100°C yopishqoqlik', 'Вязкость при 100°C'),
      L3('6.9–9.3', '6.9–9.3', '6.9–9.3'),
      L3('9.3–12.5', '9.3–12.5', '9.3–12.5'),
      L3('12.5–16.3', '12.5–16.3', '12.5–16.3'),
      L3('12.5–16.3', '12.5–16.3', '12.5–16.3'),
      L3('15.0–18.0', '15.0–18.0', '15.0–18.0'),
    ],
    [
      L3('HTHS ҳимоя', 'HTHS himoya', 'Защита HTHS'),
      L3('2.6–2.8', '2.6–2.8', '2.6–2.8'),
      L3('2.9–3.2', '2.9–3.2', '2.9–3.2'),
      L3('3.5–3.8', '3.5–3.8', '3.5–3.8'),
      L3('3.2–3.5', '3.2–3.5', '3.2–3.5'),
      L3('3.5–4.0', '3.5–4.0', '3.5–4.0'),
    ],
    [
      L3('Ёнилғи тежаш', 'Yonilg‘i tejash', 'Экономия топлива'),
      L3('⭐⭐⭐⭐⭐', '⭐⭐⭐⭐⭐', '⭐⭐⭐⭐⭐'),
      L3('⭐⭐⭐⭐', '⭐⭐⭐⭐', '⭐⭐⭐⭐'),
      L3('⭐⭐⭐', '⭐⭐⭐', '⭐⭐⭐'),
      L3('⭐⭐', '⭐⭐', '⭐⭐'),
      L3('⭐', '⭐', '⭐'),
    ],
    [
      L3('Двигател ҳимояси', 'Dvigatel himoyasi', 'Защита двигателя'),
      L3('⭐⭐', '⭐⭐', '⭐⭐'),
      L3('⭐⭐⭐⭐', '⭐⭐⭐⭐', '⭐⭐⭐⭐'),
      L3('⭐⭐⭐⭐⭐', '⭐⭐⭐⭐⭐', '⭐⭐⭐⭐⭐'),
      L3('⭐⭐⭐⭐', '⭐⭐⭐⭐', '⭐⭐⭐⭐'),
      L3('⭐⭐⭐', '⭐⭐⭐', '⭐⭐⭐'),
    ],
    [
      L3('Мой сарфи', 'Moy sarfi', 'Расход масла'),
      L3('Ортади', 'Ortadi', 'Растёт'),
      L3('Нормал', 'Normal', 'Норма'),
      L3('Камаяди', 'Kamayadi', 'Снижается'),
      L3('Камаяди', 'Kamayadi', 'Снижается'),
      L3('Жуда камаяди', 'Juda kamayadi', 'Сильно снижается'),
    ],
    [
      L3('Chevrolet', 'Chevrolet', 'Chevrolet'),
      L3('Dexos1 G3', 'Dexos1 G3', 'Dexos1 G3'),
      L3('✅ ЗАВОД', '✅ ZAVOD', '✅ ЗАВОД'),
      L3('150к+ / LPG', '150k+ / LPG', '150к+ / LPG'),
      L3('Фақат 250к+', 'Faqat 250k+', 'Только 250к+'),
      L3('Фақат 300к+', 'Faqat 300k+', 'Только 300к+'),
    ],
  ];

  /// Kilometraj va yoqilg'i turiga qarab mos mahsulotlarni filtrlash.
  static List<OilRefProduct> recommend({
    required int mileageKm,
    bool isLpg = false,
  }) {
    final OilRefType targetType;
    if (mileageKm < 150000) {
      targetType = OilRefType.full;
    } else if (mileageKm < 250000) {
      targetType = OilRefType.full;
    } else {
      targetType = OilRefType.semi;
    }

    var filtered = all.where((p) => p.oilType == targetType).toList();
    if (isLpg) {
      filtered = filtered.where((p) => p.lpgCngCompat >= 4).toList();
    }
    filtered.sort((a, b) => b.rating.compareTo(a.rating));
    return filtered;
  }
}
