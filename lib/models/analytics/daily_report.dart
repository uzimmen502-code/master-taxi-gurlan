import 'package:cloud_firestore/cloud_firestore.dart';

/// Кундалик ҳисобот snapshot'и — `daily_reports/{YYYY-MM-DD}` ҳужжатига сақланади.
///
/// Cloud Function (планированный 20:00) yoki ilovaning ўзи генерация қилиши мумкин.
class DailyReport {
  const DailyReport({
    required this.dateKey,
    required this.generatedAt,
    required this.totalUsers,
    required this.newUsersToday,
    required this.activeUsersToday,
    required this.totalDrivers,
    required this.onlineDriversNow,
    required this.activeDriversToday,
    required this.todayOrdersTotal,
    required this.todayOrdersByStatus,
    required this.todayOrdersByType,
    required this.todayRejectReasons,
    required this.todayTripsTotal,
    required this.todayTripsByStatus,
    required this.todayTripsByTaxiType,
    required this.todayRevenue,
    required this.todayRevenueByModule,
    required this.todayCashChange,
    required this.weekRevenue,
    required this.monthRevenue,
    required this.peakHour,
    required this.cancellationRate,
    required this.avgOrderValue,
    required this.avgTripValue,
    required this.totalWalletBalance,
    required this.pendingPayouts,
    required this.pendingPayoutsAmount,
    required this.blockedUsers,
    required this.topProducts,
    required this.topRoutes,
    required this.topDrivers,
    required this.notes,
  });

  /// `YYYY-MM-DD`.
  final String dateKey;
  final DateTime generatedAt;

  final int totalUsers;
  final int newUsersToday;
  final int activeUsersToday;

  final int totalDrivers;
  final int onlineDriversNow;
  final int activeDriversToday;

  final int todayOrdersTotal;
  final Map<String, int> todayOrdersByStatus;
  final Map<String, int> todayOrdersByType;
  final Map<String, int> todayRejectReasons;

  final int todayTripsTotal;
  final Map<String, int> todayTripsByStatus;
  final Map<String, int> todayTripsByTaxiType;

  final int todayRevenue;
  final Map<String, int> todayRevenueByModule;
  final int todayCashChange;

  final int weekRevenue;
  final int monthRevenue;

  final int peakHour;
  final double cancellationRate;
  final double avgOrderValue;
  final double avgTripValue;

  final int totalWalletBalance;
  final int pendingPayouts;
  final int pendingPayoutsAmount;
  final int blockedUsers;

  /// Top-5 рўйхатлар — {label, value}.
  final List<Map<String, Object?>> topProducts;
  final List<Map<String, Object?>> topRoutes;
  final List<Map<String, Object?>> topDrivers;

  /// Қўшимча эслатмалар (хатоликлар, диққат қилишга арзийдиган).
  final List<String> notes;

  Map<String, dynamic> toMap() {
    return {
      'dateKey': dateKey,
      'generatedAt': Timestamp.fromDate(generatedAt),
      'totalUsers': totalUsers,
      'newUsersToday': newUsersToday,
      'activeUsersToday': activeUsersToday,
      'totalDrivers': totalDrivers,
      'onlineDriversNow': onlineDriversNow,
      'activeDriversToday': activeDriversToday,
      'todayOrdersTotal': todayOrdersTotal,
      'todayOrdersByStatus': todayOrdersByStatus,
      'todayOrdersByType': todayOrdersByType,
      'todayRejectReasons': todayRejectReasons,
      'todayTripsTotal': todayTripsTotal,
      'todayTripsByStatus': todayTripsByStatus,
      'todayTripsByTaxiType': todayTripsByTaxiType,
      'todayRevenue': todayRevenue,
      'todayRevenueByModule': todayRevenueByModule,
      'todayCashChange': todayCashChange,
      'weekRevenue': weekRevenue,
      'monthRevenue': monthRevenue,
      'peakHour': peakHour,
      'cancellationRate': cancellationRate,
      'avgOrderValue': avgOrderValue,
      'avgTripValue': avgTripValue,
      'totalWalletBalance': totalWalletBalance,
      'pendingPayouts': pendingPayouts,
      'pendingPayoutsAmount': pendingPayoutsAmount,
      'blockedUsers': blockedUsers,
      'topProducts': topProducts,
      'topRoutes': topRoutes,
      'topDrivers': topDrivers,
      'notes': notes,
    };
  }

  factory DailyReport.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return DailyReport(
      dateKey: (d['dateKey'] ?? doc.id) as String,
      generatedAt:
          (d['generatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      totalUsers: (d['totalUsers'] as num?)?.toInt() ?? 0,
      newUsersToday: (d['newUsersToday'] as num?)?.toInt() ?? 0,
      activeUsersToday: (d['activeUsersToday'] as num?)?.toInt() ?? 0,
      totalDrivers: (d['totalDrivers'] as num?)?.toInt() ?? 0,
      onlineDriversNow: (d['onlineDriversNow'] as num?)?.toInt() ?? 0,
      activeDriversToday: (d['activeDriversToday'] as num?)?.toInt() ?? 0,
      todayOrdersTotal: (d['todayOrdersTotal'] as num?)?.toInt() ?? 0,
      todayOrdersByStatus: _intMap(d['todayOrdersByStatus']),
      todayOrdersByType: _intMap(d['todayOrdersByType']),
      todayRejectReasons: _intMap(d['todayRejectReasons']),
      todayTripsTotal: (d['todayTripsTotal'] as num?)?.toInt() ?? 0,
      todayTripsByStatus: _intMap(d['todayTripsByStatus']),
      todayTripsByTaxiType: _intMap(d['todayTripsByTaxiType']),
      todayRevenue: (d['todayRevenue'] as num?)?.toInt() ?? 0,
      todayRevenueByModule: _intMap(d['todayRevenueByModule']),
      todayCashChange: (d['todayCashChange'] as num?)?.toInt() ?? 0,
      weekRevenue: (d['weekRevenue'] as num?)?.toInt() ?? 0,
      monthRevenue: (d['monthRevenue'] as num?)?.toInt() ?? 0,
      peakHour: (d['peakHour'] as num?)?.toInt() ?? 0,
      cancellationRate:
          (d['cancellationRate'] as num?)?.toDouble() ?? 0.0,
      avgOrderValue: (d['avgOrderValue'] as num?)?.toDouble() ?? 0.0,
      avgTripValue: (d['avgTripValue'] as num?)?.toDouble() ?? 0.0,
      totalWalletBalance: (d['totalWalletBalance'] as num?)?.toInt() ?? 0,
      pendingPayouts: (d['pendingPayouts'] as num?)?.toInt() ?? 0,
      pendingPayoutsAmount:
          (d['pendingPayoutsAmount'] as num?)?.toInt() ?? 0,
      blockedUsers: (d['blockedUsers'] as num?)?.toInt() ?? 0,
      topProducts: _topList(d['topProducts']),
      topRoutes: _topList(d['topRoutes']),
      topDrivers: _topList(d['topDrivers']),
      notes: ((d['notes'] as List?)?.cast<String>()) ?? const [],
    );
  }

  static Map<String, int> _intMap(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, int>{};
    raw.forEach((k, v) {
      out[k.toString()] = (v as num?)?.toInt() ?? 0;
    });
    return out;
  }

  static List<Map<String, Object?>> _topList(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, Object?>.from(e))
        .toList();
  }
}
