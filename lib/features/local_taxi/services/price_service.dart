import 'package:cloud_firestore/cloud_firestore.dart';

/// Маҳаллий такси нарх ҳисоби.
/// Нарх `settings/prices` Firestore ҳужжатидан юкланади.
/// Fallback: `base = 3000`, `perKm = 2000`.
class PriceService {
  static double _base = 3000;
  static double _perKm = 2000;
  static bool _loaded = false;

  /// Нархларни Firestore'дан бир марта юклаш.
  static Future<void> loadPrices() async {
    if (_loaded) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('prices')
          .get();
      final data = doc.data();
      if (data != null) {
        _base = (data['local_base'] as num?)?.toDouble() ?? _base;
        _perKm = (data['local_per_km'] as num?)?.toDouble() ?? _perKm;
      }
      _loaded = true;
    } catch (_) {
      // Xato — default qiymatlar saqlanadi
    }
  }

  static double calculate({required double distanceKm}) {
    return _base + (distanceKm * _perKm);
  }

  static double get base => _base;
  static double get perKm => _perKm;
}
