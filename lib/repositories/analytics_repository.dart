import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

import '../models/analytics/daily_report.dart';
import '../models/analytics/driver_analytics.dart';
import '../models/analytics/finance_analytics.dart';
import '../models/analytics/kpi_summary.dart';
import '../models/analytics/operations_analytics.dart';
import '../models/analytics/segment.dart';
import '../models/analytics/time_series.dart';
import '../models/analytics/top_entity.dart';
import '../models/analytics/user_analytics.dart';

/// Analytics aggregation — Firestore collection'ларидан чуқур кесим.
///
/// Эслатма: Барча aggregation client-side қилинади. Иложи бўлса
/// Firestore aggregation queries (count, sum) ишлатилади.
class AnalyticsRepository {
  AnalyticsRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _drivers => _db.collection('drivers');
  CollectionReference<Map<String, dynamic>> get _orders => _db.collection('orders');
  CollectionReference<Map<String, dynamic>> get _trips => _db.collection('trips');
  CollectionReference<Map<String, dynamic>> get _schedules => _db.collection('schedules');
  CollectionReference<Map<String, dynamic>> get _driverRequests => _db.collection('driver_requests');
  CollectionReference<Map<String, dynamic>> get _payoutRequests => _db.collection('payout_requests');
  CollectionReference<Map<String, dynamic>> get _dailyReports => _db.collection('daily_reports');

  // ════════════════════════════════════════════════════════════════
  // SECTION: KPI SUMMARY (Dashboard)
  // ════════════════════════════════════════════════════════════════

  Future<KpiSummary> fetchKpiSummary() async {
    final now = DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);
    final yesterday0 = today0.subtract(const Duration(days: 1));
    final week7 = today0.subtract(const Duration(days: 7));
    final week14 = today0.subtract(const Duration(days: 14));

    // Параллел сорови
    final results = await Future.wait<dynamic>([
      _users.count().get(), // 0
      _users
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(today0))
          .count()
          .get(), // 1
      _users
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(yesterday0),
              isLessThan: Timestamp.fromDate(today0))
          .count()
          .get(), // 2
      _users
          .where('lastActiveAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(week7))
          .count()
          .get(), // 3
      _users
          .where('lastActiveAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(week14),
              isLessThan: Timestamp.fromDate(week7))
          .count()
          .get(), // 4
      _drivers.count().get(), // 5
      _drivers.where('isOnline', isEqualTo: true).count().get(), // 6
      _orders
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(today0))
          .get(), // 7 — buyurtma docs (revenue uchun ham kerак)
      _orders
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(yesterday0),
              isLessThan: Timestamp.fromDate(today0))
          .get(), // 8
      _trips
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(today0))
          .where('status', isEqualTo: 'completed')
          .get(), // 9
      _trips
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(yesterday0),
              isLessThan: Timestamp.fromDate(today0))
          .where('status', isEqualTo: 'completed')
          .get(), // 10
      _orders.where('status', whereIn: ['new', 'accepted']).count().get(), // 11
      countActiveTrips(), // 12 — haqiqiy faol safarlar
      _users.where('blockedUntil', isGreaterThan: Timestamp.fromDate(now)).count().get(), // 13
      _payoutRequests.where('status', isEqualTo: 'pending').count().get(), // 14
    ]);

    int aggCount(int i) =>
        (results[i] as AggregateQuerySnapshot).count ?? 0;

    int activeTripsCount = 0;
    if (results[12] is int) {
      activeTripsCount = results[12] as int;
    } else {
      activeTripsCount = aggCount(12);
    }

    final todaySnap = results[7] as QuerySnapshot<Map<String, dynamic>>;
    final yestSnap = results[8] as QuerySnapshot<Map<String, dynamic>>;
    final todayTripsSnap = results[9] as QuerySnapshot<Map<String, dynamic>>;
    final yestTripsSnap = results[10] as QuerySnapshot<Map<String, dynamic>>;

    final todayOrderRevenue = _sumOrderTotals(todaySnap);
    final yestOrderRevenue = _sumOrderTotals(yestSnap);
    final todayTripsRevenue = _sumTripFares(todayTripsSnap);
    final yestTripsRevenue = _sumTripFares(yestTripsSnap);

    return KpiSummary(
      totalUsers: aggCount(0),
      newUsersToday: aggCount(1),
      previousNewUsersToday: aggCount(2),
      activeUsers7d: aggCount(3),
      previousActiveUsers7d: aggCount(4),
      totalDrivers: aggCount(5),
      onlineDrivers: aggCount(6),
      todayOrders: todaySnap.docs.length,
      previousTodayOrders: yestSnap.docs.length,
      todayTrips: todayTripsSnap.docs.length,
      previousTodayTrips: yestTripsSnap.docs.length,
      todayRevenue: todayOrderRevenue + todayTripsRevenue,
      previousTodayRevenue: yestOrderRevenue + yestTripsRevenue,
      pendingOrders: aggCount(11),
      activeTrips: activeTripsCount,
      blockedUsers: aggCount(13),
      pendingPayouts: aggCount(14),
    );
  }

  int _sumOrderTotals(QuerySnapshot<Map<String, dynamic>> snap) {
    int total = 0;
    for (final d in snap.docs) {
      final data = d.data();
      final status = (data['status'] ?? '') as String;
      if (status == 'rejected' || status == 'cancelled') continue;
      total += ((data['total'] as num?)?.toInt() ?? 0);
    }
    return total;
  }

  int _sumTripFares(QuerySnapshot<Map<String, dynamic>> snap) {
    int total = 0;
    for (final d in snap.docs) {
      total += ((d.data()['fare'] as num?)?.toInt() ?? 0);
    }
    return total;
  }

  /// Haqiqiy faol safarlar — muddati o'tgan yoki eski accepted hisoblanmaydi.
  Future<int> countActiveTrips({Duration acceptedMaxAge = const Duration(hours: 24)}) async {
    final now = DateTime.now();
    final acceptedCutoff = now.subtract(acceptedMaxAge);

    final snaps = await Future.wait([
      _trips.where('status', whereIn: ['searching', 'pending']).get(),
      _trips.where('status', isEqualTo: 'accepted').get(),
    ]);

    var count = 0;
    for (final doc in snaps[0].docs) {
      final exp = (doc.data()['expiresAt'] as Timestamp?)?.toDate();
      if (exp != null && !exp.isAfter(now)) continue;
      count++;
    }
    for (final doc in snaps[1].docs) {
      final data = doc.data();
      final ref = (data['acceptedAt'] as Timestamp?)?.toDate() ??
          (data['updatedAt'] as Timestamp?)?.toDate() ??
          (data['createdAt'] as Timestamp?)?.toDate();
      if (ref != null && ref.isBefore(acceptedCutoff)) continue;
      count++;
    }
    return count;
  }

  // ════════════════════════════════════════════════════════════════
  // SECTION: USERS DEEP ANALYTICS
  // ════════════════════════════════════════════════════════════════

  Future<UserAnalytics> fetchUserAnalytics() async {
    final now = DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);
    final week0 = today0.subtract(const Duration(days: 7));
    final month0 = today0.subtract(const Duration(days: 30));
    final churnCutoff = today0.subtract(const Duration(days: 30));

    final usersSnap = await _users.get();
    final users = usersSnap.docs;

    int totalUsers = users.length;
    int newToday = 0, newWeek = 0, newMonth = 0;
    int activeDaily = 0, activeWeekly = 0, activeMonthly = 0;
    int blockedUsers = 0;
    int churnedUsers = 0;
    int usersWithWallet = 0;

    final Map<String, int> genderCounts = {};
    final Map<String, int> roleCounts = {};
    final Map<String, int> cityCounts = {};

    // Регистрация трендини ҳисоблаймиз (охирги 30 кун)
    final regTrend = <DateTime, int>{};
    for (int i = 29; i >= 0; i--) {
      final d = today0.subtract(Duration(days: i));
      regTrend[d] = 0;
    }

    for (final doc in users) {
      final d = doc.data();
      final createdAt = (d['createdAt'] as Timestamp?)?.toDate();
      final lastActive = (d['lastActiveAt'] as Timestamp?)?.toDate() ??
          (d['updatedAt'] as Timestamp?)?.toDate();
      final blockedUntil = (d['blockedUntil'] as Timestamp?)?.toDate();
      final gender = (d['gender'] ?? 'male') as String;
      final role = (d['role'] ?? 'user') as String;
      final city = (d['mfy'] ?? d['city'] ?? '—') as String;
      final balance = (d['bonusBalance'] as num?)?.toInt() ??
          (d['walletBalance'] as num?)?.toInt() ??
          0;

      genderCounts[gender] = (genderCounts[gender] ?? 0) + 1;
      roleCounts[role] = (roleCounts[role] ?? 0) + 1;
      cityCounts[city] = (cityCounts[city] ?? 0) + 1;

      if (balance > 0) usersWithWallet++;
      if (blockedUntil != null && blockedUntil.isAfter(now)) blockedUsers++;

      if (createdAt != null) {
        if (!createdAt.isBefore(today0)) newToday++;
        if (!createdAt.isBefore(week0)) newWeek++;
        if (!createdAt.isBefore(month0)) newMonth++;
        final dayKey =
            DateTime(createdAt.year, createdAt.month, createdAt.day);
        if (regTrend.containsKey(dayKey)) {
          regTrend[dayKey] = regTrend[dayKey]! + 1;
        }
      }

      if (lastActive != null) {
        if (!lastActive.isBefore(today0)) activeDaily++;
        if (!lastActive.isBefore(week0)) activeWeekly++;
        if (!lastActive.isBefore(month0)) activeMonthly++;
        if (lastActive.isBefore(churnCutoff)) churnedUsers++;
      } else {
        churnedUsers++;
      }
    }

    // Сегментациялар
    final byGender = SegmentBreakdown(
      title: 'Жинс',
      segments: [
        if (genderCounts['male'] != null)
          Segment(
            label: 'Эркак',
            value: genderCounts['male']!,
            color: AppColors.primary,
            icon: '👨',
          ),
        if (genderCounts['female'] != null)
          Segment(
            label: 'Аёл',
            value: genderCounts['female']!,
            color: const Color(0xFFE91E63),
            icon: '👩',
          ),
      ],
    );

    final byRole = SegmentBreakdown(
      title: 'Роль',
      segments: roleCounts.entries
          .map((e) => Segment(
                label: _roleLabel(e.key),
                value: e.value,
                color: _roleColor(e.key),
              ))
          .toList(),
    );

    // Город сегментlari — top 8 ko'rsаtiladi
    final cityEntries = cityCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topCities = cityEntries.take(8).toList();
    final restCount = cityEntries.skip(8).fold<int>(0, (a, b) => a + b.value);
    final byCity = SegmentBreakdown(
      title: 'Маҳалла',
      segments: [
        for (final e in topCities)
          Segment(label: e.key, value: e.value, color: _autoColor(e.key)),
        if (restCount > 0)
          Segment(
              label: 'Бошқалар',
              value: restCount,
              color: Colors.grey.shade400),
      ],
    );

    final regTrendSeries = TimeSeries(
      label: 'Янги фойдаланувчилар',
      unit: 'та',
      points: regTrend.entries
          .map((e) => TimeSeriesPoint(timestamp: e.key, value: e.value))
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp)),
    );

    // Соатлик фаоллик (бугун)
    final hourly = await _hourlyActivityHeatmap(today0);

    // Top users by orders/revenue — orders collection'дан hisoblanadi
    final topUsersData = await _topUsersFromOrders(month0);

    // ⚠️ `whereNotIn` + createdAt range = "multiple range filters" Firestore
    // чегaрaсини кeлтириб чиқaрaди. Шу сaбaб status'ни in-memory'дa фильтр
    // қилaмиз.
    final firstOrders = await _orders
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(month0))
        .get();

    // Repeat rate — бирор фойдаланувчи 2+ буюртма берганlar % i
    final orderCounts = <String, int>{};
    for (final d in firstOrders.docs) {
      final data = d.data();
      final status = (data['status'] ?? '') as String;
      if (status == 'rejected' || status == 'cancelled') continue;
      final phone = (data['userPhone'] ?? '') as String;
      if (phone.isEmpty) continue;
      orderCounts[phone] = (orderCounts[phone] ?? 0) + 1;
    }
    final uniquePhones = orderCounts.length;
    final repeatPhones =
        orderCounts.values.where((c) => c >= 2).length;
    final repeatRate = uniquePhones == 0
        ? 0.0
        : repeatPhones / uniquePhones * 100.0;
    final avgOrders = uniquePhones == 0
        ? 0.0
        : orderCounts.values.fold<int>(0, (a, b) => a + b) / uniquePhones;

    final cohort = await _weeklyCohortRetention(month0);

    return UserAnalytics(
      totalUsers: totalUsers,
      newUsersToday: newToday,
      newUsersWeek: newWeek,
      newUsersMonth: newMonth,
      activeUsersDaily: activeDaily,
      activeUsersWeekly: activeWeekly,
      activeUsersMonthly: activeMonthly,
      blockedUsers: blockedUsers,
      churnedUsers: churnedUsers,
      byGender: byGender,
      byRole: byRole,
      byCity: byCity,
      newUserRegistrationTrend: regTrendSeries,
      activityHeatmap: hourly,
      topUsersByOrders: topUsersData.byCount,
      topUsersByRevenue: topUsersData.byRevenue,
      repeatRate: repeatRate,
      avgOrdersPerUser: avgOrders,
      usersWithWallet: usersWithWallet,
      cohortRetention: cohort,
    );
  }

  Future<TimeSeries> _hourlyActivityHeatmap(DateTime today0) async {
    final tomorrow = today0.add(const Duration(days: 1));
    final snap = await _users
        .where('lastActiveAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(today0),
            isLessThan: Timestamp.fromDate(tomorrow))
        .get();
    final counts = List<int>.filled(24, 0);
    for (final d in snap.docs) {
      final t = (d.data()['lastActiveAt'] as Timestamp?)?.toDate();
      if (t == null) continue;
      counts[t.hour]++;
    }
    return TimeSeries(
      label: 'Соатлик фаоллик',
      unit: 'та',
      points: List.generate(
        24,
        (h) => TimeSeriesPoint(
            timestamp: today0.add(Duration(hours: h)), value: counts[h]),
      ),
    );
  }

  Future<({List<TopEntity> byCount, List<TopEntity> byRevenue})>
      _topUsersFromOrders(DateTime from) async {
    // `whereNotIn` + createdAt range = Firestore "multiple range filters"
    // чегaрaси. Status'ни in-memory'дa фильтр қилaмиз.
    final ordersSnap = await _orders
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .get();
    final counts = <String, int>{};
    final revenues = <String, int>{};
    final names = <String, String>{};
    for (final d in ordersSnap.docs) {
      final data = d.data();
      final status = (data['status'] ?? '') as String;
      if (status == 'rejected' || status == 'cancelled') continue;
      final phone = (data['userPhone'] ?? '') as String;
      if (phone.isEmpty) continue;
      final name = (data['userName'] ?? '') as String;
      final total = (data['total'] as num?)?.toInt() ?? 0;
      counts[phone] = (counts[phone] ?? 0) + 1;
      revenues[phone] = (revenues[phone] ?? 0) + total;
      if (name.isNotEmpty) names[phone] = name;
    }

    final byCount = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final byRevenue = revenues.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return (
      byCount: byCount
          .take(10)
          .map((e) => TopEntity(
                id: e.key,
                label: names[e.key]?.isNotEmpty == true ? names[e.key]! : e.key,
                value: e.value,
                subtitle: e.key,
                icon: '🛒',
              ))
          .toList(),
      byRevenue: byRevenue
          .take(10)
          .map((e) => TopEntity(
                id: e.key,
                label: names[e.key]?.isNotEmpty == true ? names[e.key]! : e.key,
                value: e.value,
                subtitle: '${counts[e.key] ?? 0} та буюртма',
                icon: '💎',
              ))
          .toList(),
    );
  }

  /// 30 кунлик ҳафталик когорт ретеншн.
  Future<List<TimeSeriesPoint>> _weeklyCohortRetention(
      DateTime from) async {
    // `whereNotIn` + createdAt range = Firestore "multiple range filters"
    // чегaрaси. Status'ни in-memory'дa фильтр қилaмиз.
    final snap = await _orders
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .get();
    // Hafta бошидан буюртма берган уникал фойдаланувчилар сонини олиб қарасак
    final weekBuckets = <DateTime, Set<String>>{};
    for (final d in snap.docs) {
      final data = d.data();
      final status = (data['status'] ?? '') as String;
      if (status == 'rejected' || status == 'cancelled') continue;
      final phone = (data['userPhone'] ?? '') as String;
      final t = (data['createdAt'] as Timestamp?)?.toDate();
      if (phone.isEmpty || t == null) continue;
      final weekStart = t.subtract(Duration(days: t.weekday - 1));
      final key =
          DateTime(weekStart.year, weekStart.month, weekStart.day);
      (weekBuckets[key] ??= <String>{}).add(phone);
    }
    final sorted = weekBuckets.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return sorted
        .map((e) => TimeSeriesPoint(timestamp: e.key, value: e.value.length))
        .toList();
  }

  // ════════════════════════════════════════════════════════════════
  // SECTION: DRIVERS DEEP ANALYTICS
  // ════════════════════════════════════════════════════════════════

  Future<DriverAnalytics> fetchDriverAnalytics() async {
    final now = DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);
    final week0 = today0.subtract(const Duration(days: 7));
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final results = await Future.wait<dynamic>([
      _drivers.get(), // 0
      _driverRequests
          .where('status', isEqualTo: 'pending')
          .count()
          .get(), // 1
      _trips
          .where('completedAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(today0))
          .where('status', isEqualTo: 'completed')
          .get(), // 2
      _trips
          .where('completedAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(week0))
          .where('status', isEqualTo: 'completed')
          .get(), // 3
      _schedules
          .where('date', isEqualTo: dateStr)
          .where('isActive', isEqualTo: true)
          .count()
          .get(), // 4
    ]);

    final driversSnap = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final pendingApps = (results[1] as AggregateQuerySnapshot).count ?? 0;
    final todayTripsSnap = results[2] as QuerySnapshot<Map<String, dynamic>>;
    final weekTripsSnap = results[3] as QuerySnapshot<Map<String, dynamic>>;
    final schedulesActive = (results[4] as AggregateQuerySnapshot).count ?? 0;

    int online = 0, busy = 0;
    final Map<String, int> taxiTypeCounts = {};
    final Map<String, int> ratingBuckets = {'1-2': 0, '2-3': 0, '3-4': 0, '4-5': 0};
    double sumRating = 0;
    int countRating = 0;
    final driverNames = <String, String>{};

    for (final doc in driversSnap.docs) {
      final d = doc.data();
      if ((d['isOnline'] as bool?) == true) online++;
      if ((d['isBusy'] as bool?) == true) busy++;
      final type = (d['taxiType'] ?? 'alone') as String;
      taxiTypeCounts[type] = (taxiTypeCounts[type] ?? 0) + 1;
      final rating = (d['rating'] as num?)?.toDouble() ?? 0;
      if (rating > 0) {
        sumRating += rating;
        countRating++;
        if (rating < 2) {
          ratingBuckets['1-2'] = ratingBuckets['1-2']! + 1;
        } else if (rating < 3) {
          ratingBuckets['2-3'] = ratingBuckets['2-3']! + 1;
        } else if (rating < 4) {
          ratingBuckets['3-4'] = ratingBuckets['3-4']! + 1;
        } else {
          ratingBuckets['4-5'] = ratingBuckets['4-5']! + 1;
        }
      }
      driverNames[doc.id] = (d['name'] ?? '') as String;
    }

    // Соатлик онлайн тренди (бугунги driver_status_log агар бўлмаса hозирги
    // ҳолатдан 24 соатлик "smooth" сериясини бўш қилиб қайтарамиз)
    final onlineTrend = TimeSeries(
      label: 'Онлайн ҳайдовчилар',
      unit: 'та',
      points: List.generate(
        24,
        (h) => TimeSeriesPoint(
            timestamp: today0.add(Duration(hours: h)), value: 0),
      ),
    );

    // Top by trips/earnings (бу ҳафта)
    final tripsByDriver = <String, int>{};
    final earningsByDriver = <String, int>{};
    for (final t in weekTripsSnap.docs) {
      final data = t.data();
      final id = (data['acceptedDriverId'] ?? '') as String;
      if (id.isEmpty) continue;
      tripsByDriver[id] = (tripsByDriver[id] ?? 0) + 1;
      earningsByDriver[id] =
          (earningsByDriver[id] ?? 0) + ((data['fare'] as num?)?.toInt() ?? 0);
    }

    final activeTodayIds = <String>{};
    for (final t in todayTripsSnap.docs) {
      final id = (t.data()['acceptedDriverId'] ?? '') as String;
      if (id.isNotEmpty) activeTodayIds.add(id);
    }
    final activeWeekIds = tripsByDriver.keys.toSet();

    final topByTrips = (tripsByDriver.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(10)
        .map((e) => TopEntity(
              id: e.key,
              label: driverNames[e.key] ?? e.key,
              value: e.value,
              subtitle: '${earningsByDriver[e.key] ?? 0} сўм',
              icon: '🛣',
            ))
        .toList();
    final topByEarnings = (earningsByDriver.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(10)
        .map((e) => TopEntity(
              id: e.key,
              label: driverNames[e.key] ?? e.key,
              value: e.value,
              subtitle: '${tripsByDriver[e.key] ?? 0} сафар',
              icon: '💰',
            ))
        .toList();

    // Top by rating (рейтинг бўйича)
    final topByRating = driversSnap.docs
        .map((d) {
          final data = d.data();
          return TopEntity(
            id: d.id,
            label: (data['name'] ?? '') as String,
            value: (data['rating'] as num?)?.toDouble() ?? 0,
            subtitle:
                '${(data['car'] ?? '') as String} · ${(data['plate'] ?? '') as String}',
            icon: '⭐',
          );
        })
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final byTaxiType = SegmentBreakdown(
      title: 'Такси тури',
      segments: taxiTypeCounts.entries
          .map((e) => Segment(
                label: _taxiTypeLabel(e.key),
                value: e.value,
                color: _taxiTypeColor(e.key),
              ))
          .toList(),
    );

    final byRating = SegmentBreakdown(
      title: 'Рейтинг',
      segments: ratingBuckets.entries
          .where((e) => e.value > 0)
          .map((e) => Segment(
                label: e.key,
                value: e.value,
                color: _ratingColor(e.key),
              ))
          .toList(),
    );

    return DriverAnalytics(
      totalDrivers: driversSnap.docs.length,
      onlineDrivers: online,
      busyDrivers: busy,
      pendingApplications: pendingApps,
      byTaxiType: byTaxiType,
      byRating: byRating,
      onlineTrend24h: onlineTrend,
      topByTrips: topByTrips,
      topByEarnings: topByEarnings,
      topByRating: topByRating.take(10).toList(),
      avgRating: countRating == 0 ? 0 : sumRating / countRating,
      avgTripsPerDriver: driversSnap.docs.isEmpty
          ? 0
          : weekTripsSnap.docs.length / driversSnap.docs.length,
      avgEarningsPerDriver: driversSnap.docs.isEmpty
          ? 0
          : (earningsByDriver.values.fold<int>(0, (a, b) => a + b) /
                  driversSnap.docs.length)
              .round(),
      activeToday: activeTodayIds.length,
      activeWeek: activeWeekIds.length,
      scheduleRegistered: schedulesActive,
    );
  }

  // ════════════════════════════════════════════════════════════════
  // SECTION: OPERATIONS ANALYTICS (orders + trips)
  // ════════════════════════════════════════════════════════════════

  Future<OperationsAnalytics> fetchOperationsAnalytics() async {
    final now = DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);
    final month0 = today0.subtract(const Duration(days: 30));

    final results = await Future.wait<dynamic>([
      _orders
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(today0))
          .get(), // 0
      _trips
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(today0))
          .get(), // 1
      _orders.where('status', whereIn: ['new', 'accepted']).count().get(), // 2
      countActiveTrips(), // 3
      _orders
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(month0))
          .get(), // 4
      _trips
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(month0))
          .get(), // 5
    ]);

    final todayOrdersSnap = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final todayTripsSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final activeOrders = (results[2] as AggregateQuerySnapshot).count ?? 0;
    final activeTrips = results[3] is int
        ? results[3] as int
        : ((results[3] as AggregateQuerySnapshot).count ?? 0);
    final monthOrdersSnap = results[4] as QuerySnapshot<Map<String, dynamic>>;
    final monthTripsSnap = results[5] as QuerySnapshot<Map<String, dynamic>>;

    // Бугунги сегментациялар
    final ordersByStatus = <String, int>{};
    final ordersByType = <String, int>{};
    final rejectReasons = <String, int>{};
    final productCounts = <String, int>{};
    for (final d in todayOrdersSnap.docs) {
      final data = d.data();
      final status = (data['status'] ?? 'new') as String;
      final type = (data['type'] ?? 'bread') as String;
      ordersByStatus[status] = (ordersByStatus[status] ?? 0) + 1;
      ordersByType[type] = (ordersByType[type] ?? 0) + 1;
      if (status == 'rejected') {
        final reason = (data['rejectReason'] ?? 'Кўрсатилмаган') as String;
        rejectReasons[reason] = (rejectReasons[reason] ?? 0) + 1;
      }
      final items = data['items'];
      if (items is List) {
        for (final it in items) {
          if (it is Map) {
            final name = (it['name'] ?? '') as String;
            final qty = (it['count'] as num?)?.toInt() ?? 1;
            if (name.isNotEmpty) {
              productCounts[name] = (productCounts[name] ?? 0) + qty;
            }
          }
        }
      }
    }

    final tripsByStatus = <String, int>{};
    final tripsByTaxiType = <String, int>{};
    final routeCounts = <String, int>{};
    for (final d in todayTripsSnap.docs) {
      final data = d.data();
      final status = (data['status'] ?? 'searching') as String;
      final type = (data['taxiType'] ?? 'alone') as String;
      tripsByStatus[status] = (tripsByStatus[status] ?? 0) + 1;
      tripsByTaxiType[type] = (tripsByTaxiType[type] ?? 0) + 1;
      final from = (data['from'] ?? data['fromAddr'] ?? data['pickupMfy'] ?? '') as String;
      final to = (data['to'] ?? data['toAddr'] ?? data['dropoffMfy'] ?? '') as String;
      if (from.isNotEmpty && to.isNotEmpty) {
        final route = '$from → $to';
        routeCounts[route] = (routeCounts[route] ?? 0) + 1;
      }
    }

    // Соатлик heatmap (бугун)
    final ordersHourly = List<int>.filled(24, 0);
    final tripsHourly = List<int>.filled(24, 0);
    for (final d in todayOrdersSnap.docs) {
      final t = (d.data()['createdAt'] as Timestamp?)?.toDate();
      if (t != null) ordersHourly[t.hour]++;
    }
    for (final d in todayTripsSnap.docs) {
      final t = (d.data()['createdAt'] as Timestamp?)?.toDate();
      if (t != null) tripsHourly[t.hour]++;
    }

    // Кунлик тренд (30 кун)
    final dayBucketsOrders = <DateTime, int>{};
    final dayBucketsTrips = <DateTime, int>{};
    for (int i = 29; i >= 0; i--) {
      final d = today0.subtract(Duration(days: i));
      dayBucketsOrders[d] = 0;
      dayBucketsTrips[d] = 0;
    }
    for (final d in monthOrdersSnap.docs) {
      final t = (d.data()['createdAt'] as Timestamp?)?.toDate();
      if (t == null) continue;
      final k = DateTime(t.year, t.month, t.day);
      if (dayBucketsOrders.containsKey(k)) {
        dayBucketsOrders[k] = dayBucketsOrders[k]! + 1;
      }
    }
    for (final d in monthTripsSnap.docs) {
      final t = (d.data()['createdAt'] as Timestamp?)?.toDate();
      if (t == null) continue;
      final k = DateTime(t.year, t.month, t.day);
      if (dayBucketsTrips.containsKey(k)) {
        dayBucketsTrips[k] = dayBucketsTrips[k]! + 1;
      }
    }

    // Эффективлик — fulfillment time (acceptedAt - createdAt)
    double sumFulfillMin = 0;
    int countFulfill = 0;
    for (final d in todayOrdersSnap.docs) {
      final data = d.data();
      final created = (data['createdAt'] as Timestamp?)?.toDate();
      final accepted = (data['acceptedAt'] as Timestamp?)?.toDate();
      if (created != null && accepted != null) {
        sumFulfillMin += accepted.difference(created).inSeconds / 60.0;
        countFulfill++;
      }
    }
    double sumTripMin = 0;
    int countTrip = 0;
    for (final d in todayTripsSnap.docs) {
      final data = d.data();
      final created = (data['createdAt'] as Timestamp?)?.toDate();
      final completed = (data['completedAt'] as Timestamp?)?.toDate();
      if (created != null && completed != null) {
        sumTripMin += completed.difference(created).inSeconds / 60.0;
        countTrip++;
      }
    }

    // Бекор қилиш %
    final totalCancellable = todayOrdersSnap.docs.length + todayTripsSnap.docs.length;
    final cancelled = (ordersByStatus['rejected'] ?? 0) +
        (ordersByStatus['cancelled'] ?? 0) +
        (tripsByStatus['cancelled'] ?? 0);
    final cancelRate =
        totalCancellable == 0 ? 0.0 : cancelled / totalCancellable * 100.0;

    // Peak hour
    int peakHour = 0;
    int peakHourValue = -1;
    for (int h = 0; h < 24; h++) {
      final v = ordersHourly[h] + tripsHourly[h];
      if (v > peakHourValue) {
        peakHourValue = v;
        peakHour = h;
      }
    }

    return OperationsAnalytics(
      todayOrders: todayOrdersSnap.docs.length,
      todayTrips: todayTripsSnap.docs.length,
      activeOrders: activeOrders,
      activeTrips: activeTrips,
      ordersByStatus: _toSegments('Буюртма статуси', ordersByStatus,
          labelOf: _orderStatusLabel, colorOf: _orderStatusColor),
      tripsByStatus: _toSegments('Сафар статуси', tripsByStatus,
          labelOf: _tripStatusLabel, colorOf: _tripStatusColor),
      ordersByType: _toSegments('Буюртма тури', ordersByType,
          labelOf: _orderTypeLabel),
      tripsByTaxiType: _toSegments('Такси тури', tripsByTaxiType,
          labelOf: _taxiTypeLabel, colorOf: _taxiTypeColor),
      rejectReasons: _toSegments('Рад сабаблари', rejectReasons),
      ordersHourlyHeatmap: TimeSeries(
        label: 'Соатлик буюртмалар',
        unit: 'та',
        points: List.generate(
            24,
            (h) => TimeSeriesPoint(
                timestamp: today0.add(Duration(hours: h)),
                value: ordersHourly[h])),
      ),
      tripsHourlyHeatmap: TimeSeries(
        label: 'Соатлик сафарлар',
        unit: 'та',
        points: List.generate(
            24,
            (h) => TimeSeriesPoint(
                timestamp: today0.add(Duration(hours: h)),
                value: tripsHourly[h])),
      ),
      ordersDailyTrend: TimeSeries(
        label: 'Кунлик буюртмалар',
        unit: 'та',
        points: dayBucketsOrders.entries
            .map((e) => TimeSeriesPoint(timestamp: e.key, value: e.value))
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp)),
      ),
      tripsDailyTrend: TimeSeries(
        label: 'Кунлик сафарлар',
        unit: 'та',
        points: dayBucketsTrips.entries
            .map((e) => TimeSeriesPoint(timestamp: e.key, value: e.value))
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp)),
      ),
      avgOrderFulfillmentMinutes:
          countFulfill == 0 ? 0 : sumFulfillMin / countFulfill,
      avgTripCompletionMinutes: countTrip == 0 ? 0 : sumTripMin / countTrip,
      cancellationRate: cancelRate,
      topOrderProducts: (productCounts.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(10)
          .map((e) => TopEntity(
                id: e.key,
                label: e.key,
                value: e.value,
                icon: '📦',
              ))
          .toList(),
      topTripRoutes: (routeCounts.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(10)
          .map((e) => TopEntity(
                id: e.key,
                label: e.key,
                value: e.value,
                icon: '🛣',
              ))
          .toList(),
      peakHour: peakHour,
    );
  }

  // ════════════════════════════════════════════════════════════════
  // SECTION: FINANCE ANALYTICS
  // ════════════════════════════════════════════════════════════════

  Future<FinanceAnalytics> fetchFinanceAnalytics() async {
    final now = DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);
    final week0 = today0.subtract(const Duration(days: 7));
    final month0 = today0.subtract(const Duration(days: 30));

    final results = await Future.wait<dynamic>([
      // ⚠️ `whereNotIn` + createdAt range = Firestore "multiple range filters"
      // чегaрaси. Status'ни in-memory'дa фильтр қилaмиз.
      _orders
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(month0))
          .get(), // 0
      _trips
          .where('completedAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(month0))
          .where('status', isEqualTo: 'completed')
          .get(), // 1
      _users.get(), // 2 (wallet balanslar)
      _payoutRequests
          .where('status', isEqualTo: 'pending')
          .get(), // 3
    ]);

    final ordersSnapRaw = results[0] as QuerySnapshot<Map<String, dynamic>>;
    // Status фильтр in-memory: rejected/cancelled оrders'ни чегирамиз.
    final ordersDocs = ordersSnapRaw.docs.where((d) {
      final s = (d.data()['status'] ?? '') as String;
      return s != 'rejected' && s != 'cancelled';
    }).toList();
    final tripsSnap = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final usersSnap = results[2] as QuerySnapshot<Map<String, dynamic>>;
    final payoutsSnap = results[3] as QuerySnapshot<Map<String, dynamic>>;

    int todayRevenue = 0, weekRevenue = 0, monthRevenue = 0;
    int totalWalletBalance = 0;
    int pendingPayoutsAmount = 0;
    int cashChange = 0;

    final byModule = <String, int>{};
    final paymentMethods = <String, int>{'cash': 0, 'wallet': 0};
    final dailyTrend = <DateTime, int>{};
    final hourly = List<int>.filled(24, 0);
    final productRevenue = <String, int>{};
    final routeRevenue = <String, int>{};

    for (int i = 29; i >= 0; i--) {
      final d = today0.subtract(Duration(days: i));
      dailyTrend[d] = 0;
    }

    // Buyurtmalar
    int sumOrderValue = 0;
    int countOrders = 0;
    for (final d in ordersDocs) {
      final data = d.data();
      final total = (data['total'] as num?)?.toInt() ?? 0;
      final cashPaid = (data['cashPaid'] as num?)?.toInt() ?? 0;
      final t = (data['createdAt'] as Timestamp?)?.toDate();
      final type = (data['type'] ?? 'bread') as String;
      if (t == null) continue;
      final dayKey = DateTime(t.year, t.month, t.day);

      monthRevenue += total;
      if (!t.isBefore(week0)) weekRevenue += total;
      if (!t.isBefore(today0)) {
        todayRevenue += total;
        hourly[t.hour] += total;
      }
      if (dailyTrend.containsKey(dayKey)) {
        dailyTrend[dayKey] = dailyTrend[dayKey]! + total;
      }
      byModule[type] = (byModule[type] ?? 0) + total;
      if (cashPaid > 0) {
        paymentMethods['cash'] = paymentMethods['cash']! + total;
      } else {
        paymentMethods['wallet'] = paymentMethods['wallet']! + total;
      }
      if (cashPaid > total) cashChange += (cashPaid - total);
      sumOrderValue += total;
      countOrders++;

      final items = data['items'];
      if (items is List) {
        for (final it in items) {
          if (it is Map) {
            final name = (it['name'] ?? '') as String;
            final price = (it['price'] as num?)?.toInt() ?? 0;
            final qty = (it['count'] as num?)?.toInt() ?? 1;
            if (name.isNotEmpty) {
              productRevenue[name] =
                  (productRevenue[name] ?? 0) + price * qty;
            }
          }
        }
      }
    }

    // Сафарлар
    int sumTripValue = 0;
    int countTrips = 0;
    for (final d in tripsSnap.docs) {
      final data = d.data();
      final fare = (data['fare'] as num?)?.toInt() ?? 0;
      final cashPaid = (data['cashPaid'] as num?)?.toInt() ?? 0;
      final t = (data['completedAt'] as Timestamp?)?.toDate();
      final type = (data['taxiType'] ?? 'alone') as String;
      if (t == null) continue;
      final dayKey = DateTime(t.year, t.month, t.day);

      monthRevenue += fare;
      if (!t.isBefore(week0)) weekRevenue += fare;
      if (!t.isBefore(today0)) {
        todayRevenue += fare;
        hourly[t.hour] += fare;
      }
      if (dailyTrend.containsKey(dayKey)) {
        dailyTrend[dayKey] = dailyTrend[dayKey]! + fare;
      }
      byModule['taxi_$type'] = (byModule['taxi_$type'] ?? 0) + fare;
      if (cashPaid > 0) {
        paymentMethods['cash'] = paymentMethods['cash']! + fare;
      } else {
        paymentMethods['wallet'] = paymentMethods['wallet']! + fare;
      }
      if (cashPaid > fare) cashChange += (cashPaid - fare);
      sumTripValue += fare;
      countTrips++;

      final from = (data['from'] ?? '') as String;
      final to = (data['to'] ?? '') as String;
      if (from.isNotEmpty && to.isNotEmpty) {
        final route = '$from → $to';
        routeRevenue[route] = (routeRevenue[route] ?? 0) + fare;
      }
    }

    // Wallet balanslar
    for (final u in usersSnap.docs) {
      final ud = u.data();
      final balance = (ud['bonusBalance'] as num?)?.toInt() ??
          (ud['walletBalance'] as num?)?.toInt() ??
          0;
      if (balance > 0) totalWalletBalance += balance;
    }

    for (final p in payoutsSnap.docs) {
      pendingPayoutsAmount +=
          (p.data()['amount'] as num?)?.toInt() ?? 0;
    }

    final revenueByModule = SegmentBreakdown(
      title: 'Тушум модул бўйича',
      segments: byModule.entries
          .map((e) => Segment(
                label: _moduleLabel(e.key),
                value: e.value,
                color: _moduleColor(e.key),
              ))
          .toList(),
    );

    final paymentSegments = SegmentBreakdown(
      title: 'Тўлов методи',
      segments: paymentMethods.entries
          .where((e) => e.value > 0)
          .map((e) => Segment(
                label: e.key == 'cash' ? 'Нақд' : 'Кошелёк',
                value: e.value,
                color: e.key == 'cash'
                    ? AppColors.primary
                    : AppColors.primary,
                icon: e.key == 'cash' ? '💵' : '💳',
              ))
          .toList(),
    );

    return FinanceAnalytics(
      todayRevenue: todayRevenue,
      weekRevenue: weekRevenue,
      monthRevenue: monthRevenue,
      totalWalletBalance: totalWalletBalance,
      pendingPayouts: payoutsSnap.docs.length,
      pendingPayoutsAmount: pendingPayoutsAmount,
      revenueByModule: revenueByModule,
      paymentMethods: paymentSegments,
      revenueDailyTrend: TimeSeries(
        label: 'Кунлик тушум',
        unit: 'сўм',
        points: dailyTrend.entries
            .map((e) => TimeSeriesPoint(timestamp: e.key, value: e.value))
            .toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp)),
      ),
      revenueHourly: TimeSeries(
        label: 'Соатлик тушум',
        unit: 'сўм',
        points: List.generate(
            24,
            (h) => TimeSeriesPoint(
                timestamp: today0.add(Duration(hours: h)),
                value: hourly[h])),
      ),
      topProducts: (productRevenue.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(10)
          .map((e) => TopEntity(
                id: e.key,
                label: e.key,
                value: e.value,
                icon: '🥖',
              ))
          .toList(),
      topRoutes: (routeRevenue.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(10)
          .map((e) => TopEntity(
                id: e.key,
                label: e.key,
                value: e.value,
                icon: '🛣',
              ))
          .toList(),
      avgOrderValue: countOrders == 0 ? 0 : sumOrderValue / countOrders,
      avgTripValue: countTrips == 0 ? 0 : sumTripValue / countTrips,
      cashChangeIssued: cashChange,
    );
  }

  // ════════════════════════════════════════════════════════════════
  // SECTION: DAILY REPORT
  // ════════════════════════════════════════════════════════════════

  /// Бугунги (`YYYY-MM-DD`) тўлиқ ҳисоботни ясаб Firestore'га сақлайди.
  Future<DailyReport> generateAndSaveDailyReport({DateTime? at}) async {
    final now = at ?? DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day);
    final dateKey =
        '${today0.year}-${today0.month.toString().padLeft(2, '0')}-${today0.day.toString().padLeft(2, '0')}';

    final kpi = await fetchKpiSummary();
    final users = await fetchUserAnalytics();
    final drivers = await fetchDriverAnalytics();
    final ops = await fetchOperationsAnalytics();
    final fin = await fetchFinanceAnalytics();

    final notes = <String>[];
    if (ops.cancellationRate > 20) {
      notes.add(
          '⚠️ Бекор қилиш % юқори: ${ops.cancellationRate.toStringAsFixed(1)}%');
    }
    if (fin.pendingPayouts > 0) {
      notes.add(
          '💰 ${fin.pendingPayouts} та кутаётган payout: ${fin.pendingPayoutsAmount} сўм');
    }
    if (kpi.blockedUsers > 5) {
      notes.add('🚫 ${kpi.blockedUsers} та фойдаланувчи блокда');
    }
    if (drivers.pendingApplications > 0) {
      notes.add(
          '📝 ${drivers.pendingApplications} та ҳайдовчи аризаси кутмоқда');
    }
    if (ops.avgOrderFulfillmentMinutes > 60) {
      notes.add(
          '⏱ Буюртма ўртача қабул вақти: ${ops.avgOrderFulfillmentMinutes.toStringAsFixed(0)} дақ');
    }

    final report = DailyReport(
      dateKey: dateKey,
      generatedAt: now,
      totalUsers: kpi.totalUsers,
      newUsersToday: kpi.newUsersToday,
      activeUsersToday: users.activeUsersDaily,
      totalDrivers: kpi.totalDrivers,
      onlineDriversNow: kpi.onlineDrivers,
      activeDriversToday: drivers.activeToday,
      todayOrdersTotal: ops.todayOrders,
      todayOrdersByStatus: {
        for (final s in ops.ordersByStatus.segments) s.label: s.value.toInt(),
      },
      todayOrdersByType: {
        for (final s in ops.ordersByType.segments) s.label: s.value.toInt(),
      },
      todayRejectReasons: {
        for (final s in ops.rejectReasons.segments) s.label: s.value.toInt(),
      },
      todayTripsTotal: ops.todayTrips,
      todayTripsByStatus: {
        for (final s in ops.tripsByStatus.segments) s.label: s.value.toInt(),
      },
      todayTripsByTaxiType: {
        for (final s in ops.tripsByTaxiType.segments)
          s.label: s.value.toInt(),
      },
      todayRevenue: fin.todayRevenue,
      todayRevenueByModule: {
        for (final s in fin.revenueByModule.segments) s.label: s.value.toInt(),
      },
      todayCashChange: fin.cashChangeIssued,
      weekRevenue: fin.weekRevenue,
      monthRevenue: fin.monthRevenue,
      peakHour: ops.peakHour,
      cancellationRate: ops.cancellationRate,
      avgOrderValue: fin.avgOrderValue,
      avgTripValue: fin.avgTripValue,
      totalWalletBalance: fin.totalWalletBalance,
      pendingPayouts: fin.pendingPayouts,
      pendingPayoutsAmount: fin.pendingPayoutsAmount,
      blockedUsers: kpi.blockedUsers,
      topProducts: ops.topOrderProducts
          .take(5)
          .map((e) => {'label': e.label, 'value': e.value})
          .toList(),
      topRoutes: ops.topTripRoutes
          .take(5)
          .map((e) => {'label': e.label, 'value': e.value})
          .toList(),
      topDrivers: drivers.topByTrips
          .take(5)
          .map((e) => {'label': e.label, 'value': e.value})
          .toList(),
      notes: notes,
    );

    await _dailyReports.doc(dateKey).set(report.toMap());
    return report;
  }

  /// Маълум кун учун ҳисоботни ўқиш (Firestore'дан, кэшланган бўлса
  /// сервергa тегмайди).
  Future<DailyReport?> getDailyReport(String dateKey) async {
    final doc = await _dailyReports.doc(dateKey).get();
    if (!doc.exists) return null;
    return DailyReport.fromDoc(doc);
  }

  Future<List<DailyReport>> recentDailyReports({int limit = 30}) async {
    final snap = await _dailyReports
        .orderBy('dateKey', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map(DailyReport.fromDoc).toList();
  }

  // ════════════════════════════════════════════════════════════════
  // HELPERS
  // ════════════════════════════════════════════════════════════════

  SegmentBreakdown _toSegments(
    String title,
    Map<String, int> counts, {
    String Function(String)? labelOf,
    Color Function(String)? colorOf,
  }) {
    return SegmentBreakdown(
      title: title,
      segments: counts.entries
          .map((e) => Segment(
                label: labelOf?.call(e.key) ?? e.key,
                value: e.value,
                color: colorOf?.call(e.key) ?? _autoColor(e.key),
              ))
          .toList(),
    );
  }

  static String _roleLabel(String r) {
    switch (r) {
      case 'admin':
        return 'Админ';
      case 'driver':
        return 'Ҳайдовчи';
      case 'courier':
        return 'Курьер';
      default:
        return 'Фойдаланувчи';
    }
  }

  static Color _roleColor(String r) {
    switch (r) {
      case 'admin':
        return const Color(0xFFB71C1C);
      case 'driver':
        return AppColors.primary;
      case 'courier':
        return AppColors.primary;
      default:
        return AppColors.primary;
    }
  }

  static String _taxiTypeLabel(String t) {
    switch (t) {
      case 'marshrut':
        return 'Маршрут';
      case 'intercity':
        return 'Шаҳарлараро';
      case 'alone':
        return 'Алоҳида';
      default:
        return t;
    }
  }

  static Color _taxiTypeColor(String t) {
    switch (t) {
      case 'marshrut':
        return AppColors.primaryDark;
      case 'intercity':
        return AppColors.primary;
      case 'alone':
        return AppColors.primary;
      default:
        return Colors.grey;
    }
  }

  static String _orderStatusLabel(String s) {
    switch (s) {
      case 'new':
        return 'Янги';
      case 'accepted':
        return 'Қабул';
      case 'ready':
        return 'Тайёр';
      case 'delivered':
        return 'Етказилди';
      case 'rejected':
        return 'Рад';
      case 'cancelled':
        return 'Бекор';
      default:
        return s;
    }
  }

  static Color _orderStatusColor(String s) {
    switch (s) {
      case 'new':
        return AppColors.primary;
      case 'accepted':
        return AppColors.primary;
      case 'ready':
        return AppColors.primary;
      case 'delivered':
        return const Color(0xFF388E3C);
      case 'rejected':
      case 'cancelled':
        return const Color(0xFFB71C1C);
      default:
        return Colors.grey;
    }
  }

  static String _tripStatusLabel(String s) {
    switch (s) {
      case 'searching':
        return 'Қидирувда';
      case 'pending':
        return 'Кутилмоқда';
      case 'accepted':
        return 'Қабул';
      case 'completed':
        return 'Якунланган';
      case 'cancelled':
        return 'Бекор';
      case 'rejected':
        return 'Рад';
      case 'expired':
        return 'Муддати ўтган';
      case 'no_seats':
        return 'Жой йўқ';
      default:
        return s;
    }
  }

  static Color _tripStatusColor(String s) {
    switch (s) {
      case 'searching':
      case 'pending':
        return AppColors.primary;
      case 'accepted':
        return AppColors.primary;
      case 'completed':
        return AppColors.primary;
      case 'cancelled':
      case 'rejected':
      case 'expired':
        return const Color(0xFFB71C1C);
      default:
        return Colors.grey;
    }
  }

  static String _orderTypeLabel(String t) {
    switch (t) {
      case 'bread':
        return '🥖 Нон';
      case 'food':
        return '🍽 Овқат';
      default:
        return t;
    }
  }

  static String _moduleLabel(String k) {
    switch (k) {
      case 'bread':
        return '🥖 Нон';
      case 'food':
        return '🍽 Овқат';
      case 'taxi_alone':
        return '🚕 Алоҳида';
      case 'taxi_marshrut':
        return '🚐 Маршрут';
      case 'taxi_intercity':
        return '🚌 Шаҳарлараро';
      default:
        return k;
    }
  }

  static Color _moduleColor(String k) {
    switch (k) {
      case 'bread':
        return AppColors.primary;
      case 'food':
        return AppColors.primary;
      case 'taxi_alone':
        return AppColors.primary;
      case 'taxi_marshrut':
        return AppColors.primaryDark;
      case 'taxi_intercity':
        return AppColors.primary;
      default:
        return Colors.grey;
    }
  }

  static Color _ratingColor(String bucket) {
    switch (bucket) {
      case '4-5':
        return AppColors.primary;
      case '3-4':
        return AppColors.primary;
      case '2-3':
        return AppColors.primary;
      case '1-2':
        return const Color(0xFFB71C1C);
      default:
        return Colors.grey;
    }
  }

  /// Стрингдан барқарор ранг — палитра ишлатилади.
  static Color _autoColor(String s) {
    const palette = [
      AppColors.primary,
      AppColors.primary,
      AppColors.primary,
      AppColors.primary,
      AppColors.primaryDark,
      Color(0xFFB71C1C),
      AppColors.primaryDark,
      Color(0xFF455A64),
    ];
    final i = s.hashCode.abs() % palette.length;
    return palette[i];
  }
}
