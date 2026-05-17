/// Бир кўрсаткич учун KPI кадри — ҳозирги қиймат + аввалги давр билан тенглик
/// (delta %), мутлақ ўзгариш.
class KpiValue {
  const KpiValue({
    required this.label,
    required this.value,
    this.previous,
    this.unit = '',
    this.icon,
  });

  final String label;
  final num value;

  /// Аввалги даврдаги қиймат (бугун ⇄ кеча, шу ҳафта ⇄ ўтган ҳафта).
  final num? previous;

  /// Сўм, %, та — оптимал учун қисқа белги.
  final String unit;

  /// UI учун эмодзи — иконкадан кўра енгил.
  final String? icon;

  double? get deltaPercent {
    final p = previous;
    if (p == null || p == 0) return null;
    return (value - p) / p * 100.0;
  }

  num get deltaAbsolute {
    final p = previous ?? 0;
    return value - p;
  }

  bool get isPositive {
    final d = deltaAbsolute;
    return d >= 0;
  }
}

/// Бутун Dashboard учун асосий KPIлар тўплами.
class KpiSummary {
  const KpiSummary({
    required this.totalUsers,
    required this.newUsersToday,
    required this.activeUsers7d,
    required this.totalDrivers,
    required this.onlineDrivers,
    required this.todayOrders,
    required this.todayTrips,
    required this.todayRevenue,
    required this.pendingOrders,
    required this.activeTrips,
    required this.blockedUsers,
    required this.pendingPayouts,
    this.previousUsers,
    this.previousNewUsersToday,
    this.previousActiveUsers7d,
    this.previousTodayOrders,
    this.previousTodayTrips,
    this.previousTodayRevenue,
  });

  final int totalUsers;
  final int newUsersToday;
  final int activeUsers7d;
  final int totalDrivers;
  final int onlineDrivers;
  final int todayOrders;
  final int todayTrips;
  final int todayRevenue;
  final int pendingOrders;
  final int activeTrips;
  final int blockedUsers;
  final int pendingPayouts;

  final int? previousUsers;
  final int? previousNewUsersToday;
  final int? previousActiveUsers7d;
  final int? previousTodayOrders;
  final int? previousTodayTrips;
  final int? previousTodayRevenue;

  KpiValue get usersKpi => KpiValue(
        label: 'Фойдаланувчилар',
        value: totalUsers,
        previous: previousUsers,
        unit: 'та',
        icon: '👥',
      );

  KpiValue get newUsersTodayKpi => KpiValue(
        label: 'Бугунги янги',
        value: newUsersToday,
        previous: previousNewUsersToday,
        unit: 'та',
        icon: '🆕',
      );

  KpiValue get activeUsersKpi => KpiValue(
        label: 'Фаол (7 кун)',
        value: activeUsers7d,
        previous: previousActiveUsers7d,
        unit: 'та',
        icon: '⚡',
      );

  KpiValue get driversKpi => KpiValue(
        label: 'Ҳайдовчилар',
        value: totalDrivers,
        unit: 'та',
        icon: '🚖',
      );

  KpiValue get onlineDriversKpi => KpiValue(
        label: 'Онлайн ҳайдовчи',
        value: onlineDrivers,
        unit: 'та',
        icon: '🟢',
      );

  KpiValue get todayOrdersKpi => KpiValue(
        label: 'Бугунги буюртмалар',
        value: todayOrders,
        previous: previousTodayOrders,
        unit: 'та',
        icon: '📦',
      );

  KpiValue get todayTripsKpi => KpiValue(
        label: 'Бугунги сафарлар',
        value: todayTrips,
        previous: previousTodayTrips,
        unit: 'та',
        icon: '🛣',
      );

  KpiValue get todayRevenueKpi => KpiValue(
        label: 'Бугунги тушум',
        value: todayRevenue,
        previous: previousTodayRevenue,
        unit: 'сўм',
        icon: '💰',
      );
}
