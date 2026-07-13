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

/// Motor kilometraji → tavsiya.
class MileageReco {
  const MileageReco(this.range, this.recommendation);
  final String range;
  final String recommendation;
}

/// Model uchun motor moy hajmi.
class OilModelCapacity {
  const OilModelCapacity({
    required this.engine,
    required this.oilCapacity,
    required this.filterCapacity,
    required this.total,
  });
  final String engine;
  final String oilCapacity;
  final String filterCapacity;
  final String total;
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

  static const modelCapacities = <String, OilModelCapacity>{
    'Damas': OilModelCapacity(
      engine: '0.8L (F8C)',
      oilCapacity: '2.7',
      filterCapacity: '0.2',
      total: '2.9',
    ),
    'Matiz': OilModelCapacity(
      engine: '0.8L / 1.0L',
      oilCapacity: '2.7',
      filterCapacity: '0.2',
      total: '2.9 / 3.2',
    ),
    'Nexia 1': OilModelCapacity(
      engine: '1.5L / 1.6L',
      oilCapacity: '3.5',
      filterCapacity: '0.3',
      total: '3.8',
    ),
    'Nexia 2': OilModelCapacity(
      engine: '1.5L / 1.6L',
      oilCapacity: '3.5',
      filterCapacity: '0.3',
      total: '3.8 / 4.0',
    ),
    'Nexia 3': OilModelCapacity(
      engine: '1.5L (L2B)',
      oilCapacity: '3.7',
      filterCapacity: '0.3',
      total: '4.0',
    ),
    'Spark': OilModelCapacity(
      engine: '1.0L / 1.2L',
      oilCapacity: '3.2',
      filterCapacity: '0.2',
      total: '3.4 / 3.7',
    ),
    'Cobalt': OilModelCapacity(
      engine: '1.5L (L2B)',
      oilCapacity: '3.7',
      filterCapacity: '0.3',
      total: '4.0',
    ),
    'Gentra': OilModelCapacity(
      engine: '1.5L (B15D2)',
      oilCapacity: '3.5',
      filterCapacity: '0.3',
      total: '3.8',
    ),
    'Lacetti': OilModelCapacity(
      engine: '1.4L / 1.6L',
      oilCapacity: '3.5',
      filterCapacity: '0.3',
      total: '3.8 / 4.0',
    ),
    'Malibu': OilModelCapacity(
      engine: '1.5T / 2.0T',
      oilCapacity: '4.0',
      filterCapacity: '0.3',
      total: '4.3 / 5.0',
    ),
    'Tracker': OilModelCapacity(
      engine: '1.0T / 1.2T',
      oilCapacity: '3.5',
      filterCapacity: '0.3',
      total: '3.8 / 4.2',
    ),
  };

  static OilModelCapacity? modelCapacity(String model) =>
      modelCapacities[model];

  // ─── KILOMETRAJ BO'YICHA TAVSIYALAR ────────────────────────

  static const mileageRecos = <MileageReco>[
    MileageReco('0–80 ming km', '0W-20 yoki 5W-30 to\'liq sintetik'),
    MileageReco('80–150 ming km', '5W-30 to\'liq sintetik'),
    MileageReco('150–250 ming km', '5W-40 to\'liq sintetik'),
    MileageReco('250 ming+', '10W-40 yarim sintetik'),
    MileageReco('Moy sarflaydi', '10W-40 yoki 15W-40'),
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
