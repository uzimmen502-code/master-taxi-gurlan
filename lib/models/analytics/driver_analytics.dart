import 'segment.dart';
import 'time_series.dart';
import 'top_entity.dart';

/// Ҳайдовчилар чуқур таҳлили.
class DriverAnalytics {
  const DriverAnalytics({
    required this.totalDrivers,
    required this.onlineDrivers,
    required this.busyDrivers,
    required this.pendingApplications,
    required this.byTaxiType,
    required this.byRating,
    required this.onlineTrend24h,
    required this.topByTrips,
    required this.topByEarnings,
    required this.topByRating,
    required this.avgRating,
    required this.avgTripsPerDriver,
    required this.avgEarningsPerDriver,
    required this.activeToday,
    required this.activeWeek,
    required this.scheduleRegistered,
  });

  final int totalDrivers;
  final int onlineDrivers;
  final int busyDrivers;
  final int pendingApplications;

  // Сегментация
  final SegmentBreakdown byTaxiType; // alone/marshrut/intercity
  final SegmentBreakdown byRating; // 1-2/2-3/3-4/4-5

  // Соатлик онлайн ҳолат (охирги 24 соат)
  final TimeSeries onlineTrend24h;

  // Топ
  final List<TopEntity> topByTrips;
  final List<TopEntity> topByEarnings;
  final List<TopEntity> topByRating;

  final double avgRating;
  final double avgTripsPerDriver;
  final int avgEarningsPerDriver;

  /// Бугун камида 1 сафар бажарганлар.
  final int activeToday;
  final int activeWeek;

  /// Бугунги санасига рейс рўйхатдан ўтказганлар.
  final int scheduleRegistered;
}
