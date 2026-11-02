/// «Хабарлар» вақт ёрлиқлари — рўйхат ва чатларда ЯГОНА формат (эга, 2026-11-02:
/// бошқа иловалар каби). Аввал ҳар экранда ўз `_shortDate` нусхаси бор эди.
///
/// Вақт Тошкент бўйича (UTC+5, ёзги вақт йўқ — `formatters.dart` →
/// `tashkentDayStartUtc`), қурилма вақт зонасига боғлиқ эмас.
library;

const Duration _tashkent = Duration(hours: 5);

DateTime _tk(DateTime t) => t.toUtc().add(_tashkent);

String _two(int x) => x.toString().padLeft(2, '0');

/// Тошкент бўйича кунлар фарқи: 0 — бугун, 1 — кеча, манфий — келажак.
int inboxDaysAgo(DateTime t, DateTime now) {
  final a = _tk(t);
  final b = _tk(now);
  return DateTime.utc(b.year, b.month, b.day)
      .difference(DateTime.utc(a.year, a.month, a.day))
      .inDays;
}

/// «14:35».
String inboxClock(DateTime t) {
  final a = _tk(t);
  return '${_two(a.hour)}:${_two(a.minute)}';
}

/// Рўйхат қатори: бугун → «14:35», кеча → [yesterday], шу ҳафта (2–6 кун) →
/// ҳафта куни ([weekdays] — душанба…якшанба, 7 та), эскироқ → «31.10.26».
String inboxRowTime(
  DateTime t, {
  required DateTime now,
  required String yesterday,
  required List<String> weekdays,
}) {
  final d = inboxDaysAgo(t, now);
  if (d <= 0) return inboxClock(t);
  if (d == 1) return yesterday;
  final a = _tk(t);
  if (d < 7 && weekdays.length == 7) return weekdays[a.weekday - 1];
  return '${_two(a.day)}.${_two(a.month)}.${_two(a.year % 100)}';
}

/// Чатдаги кун ажратгичи: бугун → [today], кеча → [yesterday], бошқа → «31.10.2026».
String inboxDayLabel(
  DateTime t, {
  required DateTime now,
  required String today,
  required String yesterday,
}) {
  final d = inboxDaysAgo(t, now);
  if (d <= 0) return today;
  if (d == 1) return yesterday;
  final a = _tk(t);
  return '${_two(a.day)}.${_two(a.month)}.${a.year}';
}

/// Икки вақт Тошкент бўйича бир кунданми (ажратгич керакми).
bool inboxSameDay(DateTime a, DateTime b) => inboxDaysAgo(a, b) == 0;
