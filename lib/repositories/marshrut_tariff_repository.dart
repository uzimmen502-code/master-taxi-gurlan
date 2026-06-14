import 'package:cloud_firestore/cloud_firestore.dart';

/// Marshrut yo'nalish narxlari — `settings/app` da saqlanadi.
class MarshrutTariffRepository {
  MarshrutTariffRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> get _settings =>
      _db.collection('settings').doc('app');

  static String routeKey(String fromMfy, String toMfy) =>
      '${fromMfy.trim()}|${toMfy.trim()}';

  Stream<MarshrutTariffConfig> watchConfig() {
    return _settings.snapshots().map((snap) {
      final d = snap.data() ?? {};
      return MarshrutTariffConfig.fromMap(d);
    });
  }

  Future<MarshrutTariffConfig> getConfig() async {
    final snap = await _settings.get();
    return MarshrutTariffConfig.fromMap(snap.data() ?? {});
  }

  Future<int?> priceForRoute(String fromMfy, String toMfy) async {
    final cfg = await getConfig();
    return cfg.priceFor(fromMfy, toMfy);
  }

  Future<void> setDefaultPricePerSeat(int value) async {
    await _settings.set({
      'marshrutDefaultPricePerSeat': value.clamp(0, 9999999),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> setRoutePrice({
    required String fromMfy,
    required String toMfy,
    required int pricePerSeat,
  }) async {
    final key = routeKey(fromMfy, toMfy);
    await _settings.set({
      'marshrutRoutePrices.$key': pricePerSeat.clamp(0, 9999999),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeRoutePrice({
    required String fromMfy,
    required String toMfy,
  }) async {
    final key = routeKey(fromMfy, toMfy);
    await _settings.update({
      'marshrutRoutePrices.$key': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

class MarshrutTariffConfig {
  const MarshrutTariffConfig({
    this.defaultPricePerSeat = 0,
    this.routePrices = const {},
  });

  final int defaultPricePerSeat;
  final Map<String, int> routePrices;

  factory MarshrutTariffConfig.fromMap(Map<String, dynamic> d) {
    final raw = d['marshrutRoutePrices'];
    final routes = <String, int>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k is String && v is num) routes[k] = v.toInt();
      });
    }
    return MarshrutTariffConfig(
      defaultPricePerSeat:
          (d['marshrutDefaultPricePerSeat'] as num?)?.toInt() ?? 0,
      routePrices: routes,
    );
  }

  int? priceFor(String fromMfy, String toMfy) {
    final key = MarshrutTariffRepository.routeKey(fromMfy, toMfy);
    if (routePrices.containsKey(key)) return routePrices[key];
    if (defaultPricePerSeat > 0) return defaultPricePerSeat;
    return null;
  }
}
