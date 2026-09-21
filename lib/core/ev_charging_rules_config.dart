/// EV zaryadlash nuqtalari sozlamalari — Firestore `config/ev_charging`.
/// CF `functions/ev_charging.js` va Security Rules `evMaxReportsPerStation()`
/// bilan default qiymatlari mos bo'lishi kerak.
class EvChargingRulesConfig {
  const EvChargingRulesConfig({
    required this.duplicateRadiusMeters,
    required this.arrivalRadiusMeters,
    required this.maxReportsPerUserPerStation,
    required this.clusteringThreshold,
  });

  final int duplicateRadiusMeters;
  final int arrivalRadiusMeters;
  final int maxReportsPerUserPerStation;
  final int clusteringThreshold;

  static const String firestoreDocPath = 'ev_charging';
  static const String firestoreCollection = 'config';

  static const EvChargingRulesConfig defaults = EvChargingRulesConfig(
    duplicateRadiusMeters: 50,
    arrivalRadiusMeters: 50,
    maxReportsPerUserPerStation: 3,
    clusteringThreshold: 50,
  );

  factory EvChargingRulesConfig.fromMap(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return defaults;
    return EvChargingRulesConfig(
      duplicateRadiusMeters:
          _positiveInt(json['duplicateRadiusMeters'], defaults.duplicateRadiusMeters),
      arrivalRadiusMeters:
          _positiveInt(json['arrivalRadiusMeters'], defaults.arrivalRadiusMeters),
      maxReportsPerUserPerStation: _positiveInt(
          json['maxReportsPerUserPerStation'], defaults.maxReportsPerUserPerStation),
      clusteringThreshold:
          _positiveInt(json['clusteringThreshold'], defaults.clusteringThreshold),
    );
  }

  static int _positiveInt(Object? v, int fallback) {
    final n = (v is num) ? v.toInt() : int.tryParse('$v');
    if (n == null || n < 1) return fallback;
    return n;
  }
}
