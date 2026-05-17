import 'segment.dart';
import 'time_series.dart';
import 'top_entity.dart';

/// Фойдаланувчиларнинг чуқур таҳлили (vertical: умумий → детал).
class UserAnalytics {
  const UserAnalytics({
    required this.totalUsers,
    required this.newUsersToday,
    required this.newUsersWeek,
    required this.newUsersMonth,
    required this.activeUsersDaily,
    required this.activeUsersWeekly,
    required this.activeUsersMonthly,
    required this.blockedUsers,
    required this.churnedUsers,
    required this.byGender,
    required this.byRole,
    required this.byCity,
    required this.newUserRegistrationTrend,
    required this.activityHeatmap,
    required this.topUsersByOrders,
    required this.topUsersByRevenue,
    required this.repeatRate,
    required this.avgOrdersPerUser,
    required this.usersWithWallet,
    required this.cohortRetention,
  });

  // Жами кўрсаткичлар
  final int totalUsers;
  final int newUsersToday;
  final int newUsersWeek;
  final int newUsersMonth;
  final int activeUsersDaily;
  final int activeUsersWeekly;
  final int activeUsersMonthly;
  final int blockedUsers;

  /// 30 кун давомида фаоллиги бўлмаганлар.
  final int churnedUsers;

  // Сегментация (horizontal)
  final SegmentBreakdown byGender;
  final SegmentBreakdown byRole;
  final SegmentBreakdown byCity;

  // Вақт қаторлари
  final TimeSeries newUserRegistrationTrend; // охирги 30 кун
  final TimeSeries activityHeatmap; // 24 соат — соатлик фаоллик

  // Топ рўйхатлар
  final List<TopEntity> topUsersByOrders;
  final List<TopEntity> topUsersByRevenue;

  // Эффективлик
  /// Биринчи буюртмадан кейин такрор олганлар % (буюртма бўйича).
  final double repeatRate;
  final double avgOrdersPerUser;
  final int usersWithWallet;

  /// Когорт ретеншн — биринчи буюртма ҳафтаси бўйича.
  final List<TimeSeriesPoint> cohortRetention;
}
