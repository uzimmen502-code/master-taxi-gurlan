import 'schedule.dart';

/// Marshrut qidiruv natijasi: `Schedule` + foydalanuvchi GPS'iga nisbatan
/// hisoblangan masofa va taxminiy yetib kelish vaqti (ETA).
///
/// GPS topilmasa, [distanceKm] va [etaMin] `null` bo'lishi mumkin.
class ScheduleSearchResult {
  const ScheduleSearchResult({
    required this.schedule,
    this.distanceKm,
    this.etaMin,
  });

  final Schedule schedule;
  final double? distanceKm;
  final int? etaMin;
}
