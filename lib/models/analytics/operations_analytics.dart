import 'segment.dart';
import 'time_series.dart';
import 'top_entity.dart';

/// Буюртма ва сафарларга оид кенг таҳлил.
class OperationsAnalytics {
  const OperationsAnalytics({
    required this.todayOrders,
    required this.todayTrips,
    required this.activeOrders,
    required this.activeTrips,
    required this.ordersByStatus,
    required this.tripsByStatus,
    required this.ordersByType,
    required this.tripsByTaxiType,
    required this.rejectReasons,
    required this.ordersHourlyHeatmap,
    required this.tripsHourlyHeatmap,
    required this.ordersDailyTrend,
    required this.tripsDailyTrend,
    required this.avgOrderFulfillmentMinutes,
    required this.avgTripCompletionMinutes,
    required this.cancellationRate,
    required this.topOrderProducts,
    required this.topTripRoutes,
    required this.peakHour,
  });

  // Бугунги
  final int todayOrders;
  final int todayTrips;
  final int activeOrders;
  final int activeTrips;

  // Сегментация
  final SegmentBreakdown ordersByStatus; // new/accepted/ready/delivered/rejected
  final SegmentBreakdown tripsByStatus; // searching/accepted/completed/cancelled
  final SegmentBreakdown ordersByType; // bread/food/...
  final SegmentBreakdown tripsByTaxiType; // alone/marshrut/intercity
  final SegmentBreakdown rejectReasons; // нон рад этиш сабаблари

  // Вақт қаторлари
  final TimeSeries ordersHourlyHeatmap; // 24 соат
  final TimeSeries tripsHourlyHeatmap; // 24 соат
  final TimeSeries ordersDailyTrend; // охирги 30 кун
  final TimeSeries tripsDailyTrend; // охирги 30 кун

  // Эффективлик
  final double avgOrderFulfillmentMinutes;
  final double avgTripCompletionMinutes;

  /// Бекор қилинган / жами %.
  final double cancellationRate;

  final List<TopEntity> topOrderProducts;
  final List<TopEntity> topTripRoutes;

  /// Eng band soat (HH формат).
  final int peakHour;
}
