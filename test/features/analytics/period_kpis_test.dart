import 'package:ava_gurlan/models/analytics/analytics_daily.dart';
import 'package:ava_gurlan/models/analytics/dashboard_period.dart';
import 'package:ava_gurlan/models/analytics/period_kpis.dart';
import 'package:flutter_test/flutter_test.dart';

AnalyticsDaily _day({
  required String dateKey,
  int usersNew = 0,
  int usersTotal = 0,
  int newClips = 0,
  int totalClips = 0,
  int ordersCreated = 0,
  int ordersRevenue = 0,
  int tripsCompleted = 0,
  int tripsRevenue = 0,
}) {
  return AnalyticsDaily(
    dateKey: dateKey,
    usersNew: usersNew,
    usersTotal: usersTotal,
    newClips: newClips,
    totalClips: totalClips,
    ordersCreated: ordersCreated,
    ordersRevenue: ordersRevenue,
    tripsCompleted: tripsCompleted,
    tripsRevenue: tripsRevenue,
  );
}

void main() {
  test('period SUM additive, stock from last day, unique active not summed', () {
    final days = [
      _day(
        dateKey: '2026-08-01',
        usersNew: 2,
        usersTotal: 10,
        newClips: 1,
        totalClips: 5,
        ordersCreated: 3,
        ordersRevenue: 15000,
        tripsCompleted: 1,
        tripsRevenue: 8000,
      ),
      _day(
        dateKey: '2026-08-02',
        usersNew: 3,
        usersTotal: 13,
        newClips: 4,
        totalClips: 9,
        ordersCreated: 2,
        ordersRevenue: 10000,
        tripsCompleted: 2,
        tripsRevenue: 12000,
      ),
    ];
    final previous = [
      _day(
        dateKey: '2026-07-31',
        usersNew: 1,
        ordersCreated: 4,
        ordersRevenue: 5000,
        tripsRevenue: 1000,
      ),
    ];

    final kpis = PeriodKpis.fromDailyDocs(
      period: DashboardPeriod.days7,
      from: DateTime(2026, 8, 1),
      to: DateTime(2026, 8, 2),
      days: days,
      previousDays: previous,
      uniqueActiveUsers: 7,
    );

    expect(kpis.newUsers, 5);
    expect(kpis.totalUsers, 13);
    expect(kpis.uniqueActiveUsers, 7);
    expect(kpis.uniqueActiveUsers, isNot(equals(kpis.newUsers)));
    expect(kpis.newClips, 5);
    expect(kpis.totalClips, 9);
    expect(kpis.ordersCreated, 5);
    expect(kpis.revenue, 15000 + 8000 + 10000 + 12000);
    expect(kpis.previousNewUsers, 1);
    expect(kpis.previousRevenue, 6000);
    expect(kpis.fromDaily, isTrue);
    expect(kpis.needsBackfill, isFalse);
  });

  test('7-day chip is inclusive of today', () {
    final now = DateTime(2026, 8, 19, 16, 0);
    final (from, to) = DashboardPeriod.days7.range(now);
    expect(DashboardPeriodX.dateKey(from), '2026-08-13');
    expect(DashboardPeriodX.dateKey(to), '2026-08-19');
    expect(to.difference(from).inDays + 1, 7);
  });
}
