// ══════════════════════════════════════════════════════
// Йўлкира ҳисоблаш тизими
// Формула: (base + масофа×perKm + кутиш×200) × масофа_коэф × қўшимча_коэф
// `base` ва `perKm` — `settings/prices` (local_base / local_per_km) дан.
// ══════════════════════════════════════════════════════

import 'package:cloud_firestore/cloud_firestore.dart';

import 'taxi_price_region.dart';

class FareCalculator {
  // ── Базавий нархлар (settings/prices дан юкланади) ──
  static int baseFare      = 5000;  // Базавий нарх (local_base)
  static int pricePerKm    = 1500;  // 1 км учун (local_per_km)
  static const int pricePerMin   = 200;   // Кутиш: 1 дақ учун
  static const int freeWaitMins  = 3;     // Бепул кутиш дақиқаси
  static String _loadedRegionKey = '';
  static String _activeRegionKey = TaxiPriceRegion.defaultKey;

  static String get activeRegionKey => _activeRegionKey;

  /// Нархларни Firestore `settings/prices` (+ ixtiyoriy `regions`) дан юклаш.
  ///
  /// [lat]/[lng] berilsa — mintaqaviy `regions.{key}`; aks holda `local_*`.
  static Future<void> loadPrices({double? lat, double? lng}) async {
    final regionKey = lat != null && lng != null
        ? TaxiPriceRegion.resolveKey(lat: lat, lng: lng)
        : TaxiPriceRegion.defaultKey;
    if (_loadedRegionKey == regionKey) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('prices')
          .get();
      final data = doc.data();
      if (data != null) {
        final regions = data['regions'];
        Map<String, dynamic>? regionPrices;
        if (regions is Map) {
          final raw = regions[regionKey];
          if (raw is Map) {
            regionPrices = Map<String, dynamic>.from(raw);
          } else {
            final fallback = regions[TaxiPriceRegion.defaultKey];
            if (fallback is Map) {
              regionPrices = Map<String, dynamic>.from(fallback);
            }
          }
        }
        baseFare = (regionPrices?['local_base'] as num?)?.toInt() ??
            (data['local_base'] as num?)?.toInt() ??
            baseFare;
        pricePerKm = (regionPrices?['local_per_km'] as num?)?.toInt() ??
            (data['local_per_km'] as num?)?.toInt() ??
            pricePerKm;
        _activeRegionKey = regionKey;
      }
      _loadedRegionKey = regionKey;
    } catch (_) {
      // Хато — default қийматлар сақланади.
    }
  }

  // ── Масофа коэффициентлари ──
  static double distanceCoefficient(double km) {
    if (km <= 3)  return 1.0;
    if (km <= 10) return 0.9;
    if (km <= 30) return 0.8;
    if (km <= 50) return 0.7;
    return 0.6;
  }

  // ── Қўшимча коэффициент (энг каттаси танланади) ──
  static double extraCoefficient({
    bool isNight     = false,  // 23:00–06:00 → ×1.5
    bool isHoliday   = false,  // Байрам куни → ×1.3
    bool isRainy     = false,  // Ёмғир/қор   → ×1.2
    bool isUrgent    = false,  // Шошилинч    → ×1.4
  }) {
    double coef = 1.0;
    if (isNight)   coef = coef > 1.5 ? coef : 1.5;
    if (isUrgent)  coef = coef > 1.4 ? coef : 1.4;
    if (isHoliday) coef = coef > 1.3 ? coef : 1.3;
    if (isRainy)   coef = coef > 1.2 ? coef : 1.2;
    return coef;
  }

  // ── Асосий ҳисоблаш ──
  static int calculate({
    required double distanceKm,
    int waitMinutes  = 0,
    bool isNight     = false,
    bool isHoliday   = false,
    bool isRainy     = false,
    bool isUrgent    = false,
  }) {
    // Ҳақиқий кутиш (3 дақ бепул)
    final paidWait = (waitMinutes - freeWaitMins).clamp(0, 999);

    // Базавий нарх
    final base = baseFare
        + (distanceKm * pricePerKm).round()
        + (paidWait * pricePerMin);

    // Коэффициентлар
    final distCoef  = distanceCoefficient(distanceKm);
    final extraCoef = extraCoefficient(
      isNight: isNight,
      isHoliday: isHoliday,
      isRainy: isRainy,
      isUrgent: isUrgent,
    );

    final total = (base * distCoef * extraCoef).round();

    // 500 сўмга яхлитлаш
    return (total / 500).round() * 500;
  }

  // ── Тунги вақтми? ──
  static bool isNightTime() {
    final h = DateTime.now().hour;
    return h >= 23 || h < 6;
  }

  // ── Нарх диапазони (тахминий) ──
  // Масофа аниқ эмаслиги учун мин-макс кўрсатиш
  static (int min, int max) estimateRange(double distanceKm) {
    final base = calculate(distanceKm: distanceKm);
    final night = calculate(distanceKm: distanceKm, isNight: true);
    return (base, night);
  }

  // ── Форматлаш ──
  static String format(int price) {
    final s = price.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }

  // ── Тафсилот матни ──
  static String breakdown({
    required double distanceKm,
    int waitMinutes  = 0,
    bool isNight     = false,
    bool isHoliday   = false,
    bool isRainy     = false,
    bool isUrgent    = false,
  }) {
    final paidWait  = (waitMinutes - freeWaitMins).clamp(0, 999);
    final base      = baseFare + (distanceKm * pricePerKm).round() + (paidWait * pricePerMin);
    final distCoef  = distanceCoefficient(distanceKm);
    final extraCoef = extraCoefficient(
        isNight: isNight, isHoliday: isHoliday,
        isRainy: isRainy, isUrgent: isUrgent);
    final total     = calculate(
        distanceKm: distanceKm, waitMinutes: waitMinutes,
        isNight: isNight, isHoliday: isHoliday,
        isRainy: isRainy, isUrgent: isUrgent);

    final lines = <String>[];
    lines.add('Базавий: ${format(baseFare)} сўм');
    lines.add('Масофа: ${distanceKm.toStringAsFixed(1)} км × ${format(pricePerKm)} = ${format((distanceKm * pricePerKm).round())} сўм');
    if (paidWait > 0) {
      lines.add('Кутиш: $paidWait дақ × ${format(pricePerMin)} = ${format(paidWait * pricePerMin)} сўм');
    }
    lines.add('Жами (базавий): ${format(base)} сўм');
    if (distCoef != 1.0) {
      lines.add('Масофа коэф: ×${distCoef.toStringAsFixed(1)}');
    }
    if (extraCoef != 1.0) {
      final reasons = <String>[];
      if (isNight)   reasons.add('Тунги ×1.5');
      if (isUrgent)  reasons.add('Шошилинч ×1.4');
      if (isHoliday) reasons.add('Байрам ×1.3');
      if (isRainy)   reasons.add('Ёмғир ×1.2');
      lines.add('Қўшимча коэф: ${reasons.join(', ')}');
    }
    lines.add('──────────────');
    lines.add('Йўлкира: ${format(total)} сўм');
    return lines.join('\n');
  }
}