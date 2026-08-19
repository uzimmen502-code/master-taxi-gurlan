import 'package:cloud_firestore/cloud_firestore.dart';

import 'dashboard_period.dart';

/// `analytics_daily/{YYYY-MM-DD}` — бизнес коллекциялардан кунлик агрегат.
class AnalyticsDaily {
  const AnalyticsDaily({
    required this.dateKey,
    this.usersNew = 0,
    this.usersTotal = 0,
    this.newClips = 0,
    this.newShopItems = 0,
    this.newPlatformProducts = 0,
    this.newAds = 0,
    this.totalClips = 0,
    this.totalShopItems = 0,
    this.totalPlatformProducts = 0,
    this.totalAds = 0,
    this.ordersCreated = 0,
    this.ordersRevenue = 0,
    this.tripsCompleted = 0,
    this.tripsRevenue = 0,
    this.source = '',
  });

  final String dateKey;
  final int usersNew;
  final int usersTotal;
  final int newClips;
  final int newShopItems;
  final int newPlatformProducts;
  final int newAds;
  final int totalClips;
  final int totalShopItems;
  final int totalPlatformProducts;
  final int totalAds;
  final int ordersCreated;
  final int ordersRevenue;
  final int tripsCompleted;
  final int tripsRevenue;
  final String source;

  DateTime get date => DashboardPeriodX.parseDateKey(dateKey);

  int get revenue => ordersRevenue + tripsRevenue;

  factory AnalyticsDaily.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    return AnalyticsDaily.fromMap(d, fallbackId: doc.id);
  }

  factory AnalyticsDaily.fromMap(
    Map<String, dynamic> d, {
    String fallbackId = '',
  }) {
    Map<String, dynamic> nested(String key) {
      final v = d[key];
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return Map<String, dynamic>.from(v);
      return const {};
    }

    int n(Map<String, dynamic> m, String k) => (m[k] as num?)?.toInt() ?? 0;

    final users = nested('users');
    final content = nested('content');
    final commerce = nested('commerce');
    return AnalyticsDaily(
      dateKey: (d['date'] as String?) ?? fallbackId,
      usersNew: n(users, 'new'),
      usersTotal: n(users, 'total'),
      newClips: n(content, 'newClips'),
      newShopItems: n(content, 'newShopItems'),
      newPlatformProducts: n(content, 'newPlatformProducts'),
      newAds: n(content, 'newAds'),
      totalClips: n(content, 'totalClips'),
      totalShopItems: n(content, 'totalShopItems'),
      totalPlatformProducts: n(content, 'totalPlatformProducts'),
      totalAds: n(content, 'totalAds'),
      ordersCreated: n(commerce, 'ordersCreated'),
      ordersRevenue: n(commerce, 'ordersRevenue'),
      tripsCompleted: n(commerce, 'tripsCompleted'),
      tripsRevenue: n(commerce, 'tripsRevenue'),
      source: (d['source'] as String?) ?? '',
    );
  }
}
