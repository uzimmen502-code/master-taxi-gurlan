/// Туман ичида эълон: иш вақти + сақлаш муддати.
class YukLocalSchedule {
  YukLocalSchedule._();

  /// Эганинг биринчи эълони.
  static const Duration firstListingTtl = Duration(days: 60);

  /// Кейинги эълонлар.
  static const Duration nextListingTtl = Duration(days: 10);

  /// Эски ёзувлар учун default иш вақти (бут кун).
  static const int defaultWorkStartMinutes = 0;
  static const int defaultWorkEndMinutes = 24 * 60;

  static int clampMinutes(int m) => m.clamp(0, 24 * 60);

  static int timeOfDayToMinutes(int hour, int minute) =>
      clampMinutes(hour * 60 + minute);

  static String formatMinutes(int total) {
    final m = clampMinutes(total);
    if (m >= 24 * 60) return '24:00';
    final h = m ~/ 60;
    final min = m % 60;
    return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
  }

  static (int hour, int minute) splitMinutes(int total) {
    final m = clampMinutes(total);
    if (m >= 24 * 60) return (23, 59);
    return (m ~/ 60, m % 60);
  }

  /// [now] Asia/Tashkent кутиламиз (клиент локал вақти).
  static bool isWithinWorkHours({
    required int workStartMinutes,
    required int workEndMinutes,
    DateTime? now,
  }) {
    final start = clampMinutes(workStartMinutes);
    final end = clampMinutes(workEndMinutes);
    // 00:00–24:00 ёки тенг → бут кун.
    if (start == 0 && end >= 24 * 60) return true;
    if (start == end) return true;

    final t = now ?? DateTime.now();
    final m = t.hour * 60 + t.minute;

    if (start < end) {
      return m >= start && m < end;
    }
    // Кечага ўтувчи смена: 22:00–06:00
    return m >= start || m < end;
  }
}
