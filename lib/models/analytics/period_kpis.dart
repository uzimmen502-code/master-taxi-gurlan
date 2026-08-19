import 'analytics_daily.dart';
import 'dashboard_period.dart';
import 'kpi_summary.dart';
import 'time_series.dart';

/// Давр бўйича Dashboard рақамлари.
///
/// Additive = SUM(daily.new*). Stock = last day's total*. Unique active
/// injected from a live `users.lastActiveAt` count — never SUM of DAU.
class PeriodKpis {
  const PeriodKpis({
    required this.period,
    required this.from,
    required this.to,
    required this.fromDaily,
    this.needsBackfill = false,
    this.newUsers = 0,
    this.previousNewUsers,
    this.uniqueActiveUsers = 0,
    this.totalUsers = 0,
    this.newClips = 0,
    this.newShopItems = 0,
    this.newPlatformProducts = 0,
    this.newAds = 0,
    this.previousNewClips,
    this.previousNewShopItems,
    this.previousNewPlatformProducts,
    this.previousNewAds,
    this.totalClips = 0,
    this.totalShopItems = 0,
    this.totalPlatformProducts = 0,
    this.totalAds = 0,
    this.ordersCreated = 0,
    this.tripsCompleted = 0,
    this.ordersRevenue = 0,
    this.tripsRevenue = 0,
    this.previousOrdersCreated,
    this.previousTripsCompleted,
    this.previousRevenue,
    this.newUsersTrend = const TimeSeries(label: '', points: []),
    this.clipsTrend = const TimeSeries(label: '', points: []),
    this.ordersTrend = const TimeSeries(label: '', points: []),
    this.revenueTrend = const TimeSeries(label: '', points: []),
  });

  final DashboardPeriod period;
  final DateTime from;
  final DateTime to;
  final bool fromDaily;
  final bool needsBackfill;

  final int newUsers;
  final int? previousNewUsers;
  final int uniqueActiveUsers;
  final int totalUsers;

  final int newClips;
  final int newShopItems;
  final int newPlatformProducts;
  final int newAds;
  final int? previousNewClips;
  final int? previousNewShopItems;
  final int? previousNewPlatformProducts;
  final int? previousNewAds;

  final int totalClips;
  final int totalShopItems;
  final int totalPlatformProducts;
  final int totalAds;

  final int ordersCreated;
  final int tripsCompleted;
  final int ordersRevenue;
  final int tripsRevenue;
  final int? previousOrdersCreated;
  final int? previousTripsCompleted;
  final int? previousRevenue;

  final TimeSeries newUsersTrend;
  final TimeSeries clipsTrend;
  final TimeSeries ordersTrend;
  final TimeSeries revenueTrend;

  int get revenue => ordersRevenue + tripsRevenue;

  String get _newLabel {
    switch (period) {
      case DashboardPeriod.today:
        return 'Бугунги янги';
      case DashboardPeriod.allTime:
        return 'Жами янги';
      default:
        return 'Янги (${period.chipLabel})';
    }
  }

  String get _countLabel {
    switch (period) {
      case DashboardPeriod.today:
        return 'Бугунги';
      case DashboardPeriod.allTime:
        return 'Жами';
      default:
        return period.chipLabel;
    }
  }

  KpiValue get newUsersKpi => KpiValue(
        label: _newLabel,
        value: newUsers,
        previous: previousNewUsers,
        unit: 'та',
        icon: '🆕',
      );

  KpiValue get uniqueActiveKpi => KpiValue(
        label: period == DashboardPeriod.today
            ? 'Фаол (бугун)'
            : 'Фаол (${period.chipLabel})',
        value: uniqueActiveUsers,
        unit: 'та',
        icon: '⚡',
      );

  KpiValue get totalUsersKpi => KpiValue(
        label: 'Фойдаланувчилар',
        value: totalUsers,
        unit: 'та',
        icon: '👥',
      );

  KpiValue get ordersKpi => KpiValue(
        label: '$_countLabel буюртма',
        value: ordersCreated,
        previous: previousOrdersCreated,
        unit: 'та',
        icon: '📦',
      );

  KpiValue get tripsKpi => KpiValue(
        label: '$_countLabel сафар',
        value: tripsCompleted,
        previous: previousTripsCompleted,
        unit: 'та',
        icon: '🛣',
      );

  KpiValue get revenueKpi => KpiValue(
        label: '$_countLabel тушум',
        value: revenue,
        previous: previousRevenue,
        unit: 'сўм',
        icon: '💰',
      );

  KpiValue get newClipsKpi => KpiValue(
        label: 'Янги роликлар',
        value: newClips,
        previous: previousNewClips,
        unit: 'та',
        icon: '🎬',
      );

  KpiValue get totalClipsKpi => KpiValue(
        label: 'Жами роликлар',
        value: totalClips,
        unit: 'та',
        icon: '🎞',
      );

  KpiValue get newShopItemsKpi => KpiValue(
        label: 'Янги товарлар',
        value: newShopItems,
        previous: previousNewShopItems,
        unit: 'та',
        icon: '🛍',
      );

  KpiValue get totalShopItemsKpi => KpiValue(
        label: 'Жами товарлар',
        value: totalShopItems,
        unit: 'та',
        icon: '🏪',
      );

  KpiValue get newPlatformProductsKpi => KpiValue(
        label: 'Янги платформа',
        value: newPlatformProducts,
        previous: previousNewPlatformProducts,
        unit: 'та',
        icon: '📦',
      );

  KpiValue get totalPlatformProductsKpi => KpiValue(
        label: 'Платформа каталог',
        value: totalPlatformProducts,
        unit: 'та',
        icon: '🏬',
      );

  KpiValue get newAdsKpi => KpiValue(
        label: 'Янги эълонлар',
        value: newAds,
        previous: previousNewAds,
        unit: 'та',
        icon: '📢',
      );

  KpiValue get totalAdsKpi => KpiValue(
        label: 'Жами эълонлар',
        value: totalAds,
        unit: 'та',
        icon: '📋',
      );

  /// SUM additive news; stock from last day; uniqueActive passed in.
  factory PeriodKpis.fromDailyDocs({
    required DashboardPeriod period,
    required DateTime from,
    required DateTime to,
    required List<AnalyticsDaily> days,
    List<AnalyticsDaily> previousDays = const [],
    required int uniqueActiveUsers,
  }) {
    var newUsers = 0;
    var newClips = 0;
    var newShopItems = 0;
    var newPlatformProducts = 0;
    var newAds = 0;
    var ordersCreated = 0;
    var tripsCompleted = 0;
    var ordersRevenue = 0;
    var tripsRevenue = 0;
    for (final d in days) {
      newUsers += d.usersNew;
      newClips += d.newClips;
      newShopItems += d.newShopItems;
      newPlatformProducts += d.newPlatformProducts;
      newAds += d.newAds;
      ordersCreated += d.ordersCreated;
      tripsCompleted += d.tripsCompleted;
      ordersRevenue += d.ordersRevenue;
      tripsRevenue += d.tripsRevenue;
    }

    final last = days.isEmpty ? null : days.last;
    int? prevSum(int Function(AnalyticsDaily d) pick) {
      if (previousDays.isEmpty) return null;
      return previousDays.fold<int>(0, (a, d) => a + pick(d));
    }

    TimeSeries series(String label, int Function(AnalyticsDaily d) pick) {
      return TimeSeries(
        label: label,
        unit: 'та',
        points: [
          for (final d in days)
            TimeSeriesPoint(timestamp: d.date, value: pick(d)),
        ],
      );
    }

    return PeriodKpis(
      period: period,
      from: from,
      to: to,
      fromDaily: days.isNotEmpty,
      needsBackfill: days.isEmpty,
      newUsers: newUsers,
      previousNewUsers: prevSum((d) => d.usersNew),
      uniqueActiveUsers: uniqueActiveUsers,
      totalUsers: last?.usersTotal ?? 0,
      newClips: newClips,
      newShopItems: newShopItems,
      newPlatformProducts: newPlatformProducts,
      newAds: newAds,
      previousNewClips: prevSum((d) => d.newClips),
      previousNewShopItems: prevSum((d) => d.newShopItems),
      previousNewPlatformProducts: prevSum((d) => d.newPlatformProducts),
      previousNewAds: prevSum((d) => d.newAds),
      totalClips: last?.totalClips ?? 0,
      totalShopItems: last?.totalShopItems ?? 0,
      totalPlatformProducts: last?.totalPlatformProducts ?? 0,
      totalAds: last?.totalAds ?? 0,
      ordersCreated: ordersCreated,
      tripsCompleted: tripsCompleted,
      ordersRevenue: ordersRevenue,
      tripsRevenue: tripsRevenue,
      previousOrdersCreated: prevSum((d) => d.ordersCreated),
      previousTripsCompleted: prevSum((d) => d.tripsCompleted),
      previousRevenue: prevSum((d) => d.revenue),
      newUsersTrend: series('Янги фойдаланувчилар', (d) => d.usersNew),
      clipsTrend: series('Янги роликлар', (d) => d.newClips),
      ordersTrend: series('Буюртмалар', (d) => d.ordersCreated),
      revenueTrend: TimeSeries(
        label: 'Тушум',
        unit: 'сўм',
        points: [
          for (final d in days)
            TimeSeriesPoint(timestamp: d.date, value: d.revenue),
        ],
      ),
    );
  }
}
