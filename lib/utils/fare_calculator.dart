// ══════════════════════════════════════════════════════
// Йўлкира ҳисоблаш тизими
// Формула: (base + масофа×perKm + кутиш) × local_coef × масофа_коэф × қўшимча_коэф
// `base`, `perKm`, `local_coef` — `settings/prices` (admin web) дан.
// ══════════════════════════════════════════════════════

import 'package:cloud_firestore/cloud_firestore.dart';

import 'taxi_price_region.dart';

class FareCalculator {
  static int baseFare = 5000;
  static int pricePerKm = 1500;
  /// Admin web `local_coef` — (бoshlanish + km×narx) ustiga qo'llanadi.
  static double priceCoef = 1.0;
  static const int pricePerMin = 200;
  static const int freeWaitMins = 3;
  static String _activeRegionKey = TaxiPriceRegion.defaultKey;

  static String get activeRegionKey => _activeRegionKey;

  static Future<void> loadPrices({double? lat, double? lng}) async {
    final regionKey = lat != null && lng != null
        ? TaxiPriceRegion.resolveKey(lat: lat, lng: lng)
        : TaxiPriceRegion.defaultKey;
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
        priceCoef = (regionPrices?['local_coef'] as num?)?.toDouble() ??
            (data['local_coef'] as num?)?.toDouble() ??
            1.0;
        if (priceCoef <= 0) priceCoef = 1.0;
        _activeRegionKey = regionKey;
      }
    } catch (_) {}
  }

  static double distanceCoefficient(double km) {
    if (km <= 3) return 1.0;
    if (km <= 10) return 0.9;
    if (km <= 30) return 0.8;
    if (km <= 50) return 0.7;
    return 0.6;
  }

  static double extraCoefficient({
    bool isNight = false,
    bool isHoliday = false,
    bool isRainy = false,
    bool isUrgent = false,
  }) {
    double coef = 1.0;
    if (isNight) coef = coef > 1.5 ? coef : 1.5;
    if (isUrgent) coef = coef > 1.4 ? coef : 1.4;
    if (isHoliday) coef = coef > 1.3 ? coef : 1.3;
    if (isRainy) coef = coef > 1.2 ? coef : 1.2;
    return coef;
  }

  static int calculate({
    required double distanceKm,
    int waitMinutes = 0,
    bool isNight = false,
    bool isHoliday = false,
    bool isRainy = false,
    bool isUrgent = false,
  }) {
    final paidWait = (waitMinutes - freeWaitMins).clamp(0, 999);
    final base = baseFare +
        (distanceKm * pricePerKm).round() +
        (paidWait * pricePerMin);
    final distCoef = distanceCoefficient(distanceKm);
    final extraCoef = extraCoefficient(
      isNight: isNight,
      isHoliday: isHoliday,
      isRainy: isRainy,
      isUrgent: isUrgent,
    );
    final total = (base * priceCoef * distCoef * extraCoef).round();
    return (total / 500).round() * 500;
  }

  static bool isNightTime() {
    final h = DateTime.now().hour;
    return h >= 23 || h < 6;
  }

  static (int min, int max) estimateRange(double distanceKm) {
    final base = calculate(distanceKm: distanceKm);
    final night = calculate(distanceKm: distanceKm, isNight: true);
    return (base, night);
  }

  static String format(int price) {
    final s = price.toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }

  static String breakdown({
    required double distanceKm,
    int waitMinutes = 0,
    bool isNight = false,
    bool isHoliday = false,
    bool isRainy = false,
    bool isUrgent = false,
  }) {
    final paidWait = (waitMinutes - freeWaitMins).clamp(0, 999);
    final base = baseFare +
        (distanceKm * pricePerKm).round() +
        (paidWait * pricePerMin);
    final distCoef = distanceCoefficient(distanceKm);
    final extraCoef = extraCoefficient(
      isNight: isNight,
      isHoliday: isHoliday,
      isRainy: isRainy,
      isUrgent: isUrgent,
    );
    final total = calculate(
      distanceKm: distanceKm,
      waitMinutes: waitMinutes,
      isNight: isNight,
      isHoliday: isHoliday,
      isRainy: isRainy,
      isUrgent: isUrgent,
    );

    final lines = <String>[];
    lines.add('Boshlang\'ich: ${format(baseFare)} so\'m');
    lines.add(
      'Masofa: ${distanceKm.toStringAsFixed(1)} km × ${format(pricePerKm)} '
      '= ${format((distanceKm * pricePerKm).round())} so\'m',
    );
    if (paidWait > 0) {
      lines.add(
        'Kutish: $paidWait daq × ${format(pricePerMin)} '
        '= ${format(paidWait * pricePerMin)} so\'m',
      );
    }
    lines.add('Jami (asosiy): ${format(base)} so\'m');
    if (priceCoef != 1.0) {
      lines.add('Admin koeffitsient: ×${priceCoef.toStringAsFixed(2)}');
    }
    if (distCoef != 1.0) {
      lines.add('Masofa koeffitsient: ×${distCoef.toStringAsFixed(1)}');
    }
    if (extraCoef != 1.0) {
      final reasons = <String>[];
      if (isNight) reasons.add('Tungi ×1.5');
      if (isUrgent) reasons.add('Shoshilinch ×1.4');
      if (isHoliday) reasons.add('Bayram ×1.3');
      if (isRainy) reasons.add('Yomg\'ir ×1.2');
      lines.add('Qo\'shimcha koeffitsient: ${reasons.join(', ')}');
    }
    lines.add('──────────────');
    lines.add('Yo\'lkira: ${format(total)} so\'m');
    return lines.join('\n');
  }
}
