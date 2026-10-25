import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/formatters.dart';

/// Сотувчи статистикаси (6-босқич): `shop_stats/{ownerPhone}_{yyyymmdd}` кунлик ҳужжатлар йиғиндиси.
/// Ҳисоблаш қоидаси серверда (`functions/shop_stats.js`): бир харидор × бир объект × бир кун = 1, эганинг ўзи
/// саналмайди. Бу ер фақат йиғади.
class ShopStatsSummary {
  const ShopStatsSummary({
    required this.days,
    required this.shopViews,
    required this.productViews,
    required this.bySource,
    required this.items,
  });

  final int days;
  final int shopViews;
  final int productViews;

  /// Манба → кўришлар (дўкон + маҳсулот).
  final Map<String, int> bySource;

  /// Маҳсулот ID → кўришлар.
  final Map<String, int> items;

  int src(String s) => bySource[s] ?? 0;

  /// Энг кўп кўрилган маҳсулотлар (ID, сони), камайиш тартибида.
  List<MapEntry<String, int>> topItems([int n = 5]) {
    final list = items.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    return list.take(n).toList();
  }

  static int _int(Object? v) => v is num ? v.toInt() : 0;

  static Map<String, int> _map(Object? v) =>
      v is Map ? {for (final e in v.entries) '${e.key}': _int(e.value)} : const {};

  static ShopStatsSummary fromDays(List<Map<String, dynamic>> docs, {required int days}) {
    var shop = 0;
    var prod = 0;
    final src = <String, int>{};
    final items = <String, int>{};
    for (final d in docs) {
      shop += _int(d['shopViews']);
      prod += _int(d['productViews']);
      _map(d['src']).forEach((k, v) => src[k] = (src[k] ?? 0) + v);
      _map(d['items']).forEach((k, v) => items[k] = (items[k] ?? 0) + v);
    }
    return ShopStatsSummary(days: days, shopViews: shop, productViews: prod, bySource: src, items: items);
  }
}

/// Тошкент (UTC+5) куни `yyyymmdd` — сервер билан бир хил.
String shopStatsDayKey(DateTime utcNow) {
  final t = utcNow.toUtc().add(const Duration(hours: 5));
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}${two(t.month)}${two(t.day)}';
}

class ShopStatsRepository {
  ShopStatsRepository({FirebaseFirestore? db}) : _db = db;

  final FirebaseFirestore? _db;
  FirebaseFirestore get _fs => _db ?? FirebaseFirestore.instance;

  /// Охирги [days] кун: ҳар куннинг ҳужжати ID бўйича (rules: фақат эгаси `get` қилади; рўйхат ёпиқ).
  /// [days] та ўқиш; ҳужжати йўқ кун — 0.
  Future<ShopStatsSummary> fetch(String ownerPhone, {int days = 7, DateTime? now}) async {
    final owner = canonicalPhoneId(ownerPhone);
    final base = (now ?? DateTime.now()).toUtc();
    final ids = [for (var i = 0; i < days; i++) '${owner}_${shopStatsDayKey(base.subtract(Duration(days: i)))}'];
    final snaps = await Future.wait(ids.map((id) => _fs.collection('shop_stats').doc(id).get()));
    return ShopStatsSummary.fromDays([for (final s in snaps) if (s.exists) s.data() ?? const {}], days: days);
  }
}
