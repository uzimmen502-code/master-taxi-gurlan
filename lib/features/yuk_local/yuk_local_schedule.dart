/// Туман ичида эълон: иш вақти + сақлаш муддати.
class YukLocalSchedule {
  YukLocalSchedule._();

  /// Эганинг биринчи эълони.
  static const Duration firstListingTtl = Duration(days: 60);

  /// Кейинги эълонлар.
  static const Duration nextListingTtl = Duration(days: 30);

  // Муддат ҚАРОРИ серверда (`functions/yuk_local.js`, эга 2026-10-31):
  // яратилганда 60/30 кун, «Узайтириш» +30 кун, муддат тугашига ≤3 кун
  // қолганда ёки ўтгач узайтирилади, ўтганидан 30 кун кейин ўчирилади.
  // Қуйидагилар фақат UI учун (тугма кўрсатиш) — сервер барибир текширади.

  /// «Узайтириш» тугмаси шундан кам қолганда кўринади.
  static const Duration renewWindow = Duration(days: 3);

  /// Муддати ўтган эълон шунча вақт эгада кўринади, кейин сервер ўчиради.
  static const Duration expiredGrace = Duration(days: 30);

  /// Бир рақамга фаол эълонлар чегараси (эга 2026-10-31). Сервер триггери
  /// 11-чисини ўчиради; бу ерда фақат форма очилмаслиги учун.
  static const int maxActiveListings = 10;

  /// Фаол эълонлар сони — муддати йўқ (эски) ёки ҳали ўтмаган [expiries].
  static int activeCount(Iterable<DateTime?> expiries, {DateTime? now}) {
    final t = now ?? DateTime.now();
    return expiries.where((e) => e == null || e.isAfter(t)).length;
  }

  /// Яна битта янги эълон бериш мумкинми.
  static bool canAddListing(Iterable<DateTime?> expiries, {DateTime? now}) =>
      activeCount(expiries, now: now) < maxActiveListings;

  /// Эга узайтира оладими: муддати ≤3 кун қолган ёки ўтган (30 кун ичида).
  static bool canRenew(DateTime? expiresAt, {DateTime? now}) {
    if (expiresAt == null) return false;
    final t = now ?? DateTime.now();
    if (expiresAt.add(expiredGrace).isBefore(t)) return false;
    return expiresAt.difference(t) <= renewWindow;
  }

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
