import 'segment.dart';
import 'top_entity.dart';

/// TV Market playback sifat metrikalari — `tv_clips/{id}.playbackStats`
/// denormalized counter'laridan yig'ilgan (video_engine loyihasi, 5-bosqich).
///
/// Eslatma: hozircha vaqt-qatorlari (kunlik trend, soatlik heatmap) yo'q —
/// ma'lumot faqat per-klip jamlangan hisoblagichlar, alohida rollup hujjat
/// emas. Shuning uchun bu yerda faqat "hozirgi holat" ko'rsatkichlari bor.
class TvPlaybackAnalytics {
  const TvPlaybackAnalytics({
    required this.clipsWithData,
    required this.totalViews,
    required this.avgFirstFrameMs,
    required this.rebufferRatio,
    required this.completionRate,
    required this.skipRate,
    required this.errorRate,
    required this.outcomeBreakdown,
    required this.topViewed,
  });

  /// Kamida bitta ko'rish qayd etilgan klip soni (skanerlangan namunada).
  final int clipsWithData;
  final int totalViews;

  /// O'rtacha birinchi kadr vaqti (ms).
  final double avgFirstFrameMs;

  /// bufferMs / watchedMs, foizda.
  final double rebufferRatio;

  /// completedViews / totalViews, foizda.
  final double completionRate;

  /// skippedViews / totalViews, foizda.
  final double skipRate;

  /// errors / totalViews, foizda.
  final double errorRate;

  /// completed / skipped / boshqa — donut chart uchun.
  final SegmentBreakdown outcomeBreakdown;

  final List<TopEntity> topViewed;

  static const empty = TvPlaybackAnalytics(
    clipsWithData: 0,
    totalViews: 0,
    avgFirstFrameMs: 0,
    rebufferRatio: 0,
    completionRate: 0,
    skipRate: 0,
    errorRate: 0,
    outcomeBreakdown: SegmentBreakdown(title: 'Natija', segments: []),
    topViewed: [],
  );
}
