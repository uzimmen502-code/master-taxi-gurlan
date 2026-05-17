import 'segment.dart';
import 'time_series.dart';
import 'top_entity.dart';

/// Молиявий чуқур таҳлил.
class FinanceAnalytics {
  const FinanceAnalytics({
    required this.todayRevenue,
    required this.weekRevenue,
    required this.monthRevenue,
    required this.totalWalletBalance,
    required this.pendingPayouts,
    required this.pendingPayoutsAmount,
    required this.revenueByModule,
    required this.paymentMethods,
    required this.revenueDailyTrend,
    required this.revenueHourly,
    required this.topProducts,
    required this.topRoutes,
    required this.avgOrderValue,
    required this.avgTripValue,
    required this.cashChangeIssued,
  });

  final int todayRevenue;
  final int weekRevenue;
  final int monthRevenue;

  /// Барча фойдаланувчилардаги жами кошелёк баланси.
  final int totalWalletBalance;

  /// Кутаётган payout сўровлар сони.
  final int pendingPayouts;

  /// Кутаётган payout суммаси (jami).
  final int pendingPayoutsAmount;

  /// Модуль бўйича тушум — нон/тайёр овқат/такси/маршрут/интерсити.
  final SegmentBreakdown revenueByModule;

  /// Тўлов методи — нақд / кошелёк (qisqman).
  final SegmentBreakdown paymentMethods;

  // Вақт қаторлари
  final TimeSeries revenueDailyTrend; // охирги 30 кун
  final TimeSeries revenueHourly; // бугунги 24 соат

  final List<TopEntity> topProducts;
  final List<TopEntity> topRoutes;

  final double avgOrderValue;
  final double avgTripValue;

  /// Қайтарилган қолдиқ (cashChange) — кошелёкка қўшилган маблағ.
  final int cashChangeIssued;
}
