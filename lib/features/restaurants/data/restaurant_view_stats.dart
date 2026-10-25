import 'package:cloud_firestore/cloud_firestore.dart';

import '../../my_shop/shop_stats.dart';

/// Кафе-ресторан кўришлари (2026-10-25): `restaurants/{rid}/view_stats/{yyyymmdd}` кунлик ҳужжатлар йиғиндиси.
/// Санаш қоидаси серверда (`functions/shop_stats.js`, дўкон билан бир хил): бир харидор × бир объект × бир кун = 1,
/// ресторан а'золари саналмайди. Модел ва экран — дўконники ([ShopStatsSummary], `ShopStatsScreen`).
class RestaurantViewStatsRepository {
  RestaurantViewStatsRepository({FirebaseFirestore? db}) : _db = db;

  final FirebaseFirestore? _db;
  FirebaseFirestore get _fs => _db ?? FirebaseFirestore.instance;

  /// Охирги [days] кун: ҳар кун ID бўйича `get` (rules: фақат а'зо; рўйхат ёпиқ). Ҳужжати йўқ кун — 0.
  Future<ShopStatsSummary> fetch(String restaurantId, {int days = 7, DateTime? now}) async {
    final base = (now ?? DateTime.now()).toUtc();
    final col = _fs.collection('restaurants').doc(restaurantId).collection('view_stats');
    final snaps = await Future.wait([
      for (var i = 0; i < days; i++) col.doc(shopStatsDayKey(base.subtract(Duration(days: i)))).get(),
    ]);
    return ShopStatsSummary.fromDays(
      [for (final s in snaps) if (s.exists) s.data() ?? const {}],
      days: days,
      mainKey: 'restaurantViews',
      itemKey: 'dishViews',
    );
  }
}
