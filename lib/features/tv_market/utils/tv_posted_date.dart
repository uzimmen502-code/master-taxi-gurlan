/// Видео устидаги «жойланган сана» белгиси (эга қарори, 2026-11-02).
///
/// Сана — клипнинг СЕРВЕР вақти (`createdAt`): клиент уни яратишда фақат
/// `serverTimestamp()` ёза олади (firestore.rules → `tv_clips` create:
/// `createdAt == request.time`), кейин ўзгартира олмайди (update
/// блок-рўйхатида). Таҳрир (`updateOwnClip`) `createdAt`га тегмайди —
/// жойланган сана ўзгармайди.
///
/// Фақат ЯНГИ клиплар: [kTvPostedDateSince] дан олдин жойланганларига
/// сана чиқмайди (эскиларига тегилмайди).
library;

/// Шу пайтдан (UTC) кейин жойланган клипларда сана кўринади — rules'даги
/// `createdAt == request.time` текшируви жонли бўлган пайт. Ундан олдинги
/// клипларнинг `createdAt`и клиентдан келган бўлиши мумкин эди.
final DateTime kTvPostedDateSince = DateTime.utc(2026, 11, 2, 17, 30);

/// Тошкент = UTC+5, ёзги вақт йўқ (`formatters.dart` → `tashkentDayStartUtc`).
const Duration _tashkentOffset = Duration(hours: 5);

/// Белги матни: шу кун (Тошкент бўйича) → «Бугун, 14:35», аввалги кунлар →
/// «31.10.2026». Сана йўқ ёки клип эски бўлса — `null` (белги чиқмайди).
///
/// [todayWord] — таржима қилинган «Бугун» (`tv_posted_today`).
String? tvPostedDateLabel(
  DateTime? createdAt, {
  required DateTime now,
  required String todayWord,
}) {
  if (createdAt == null) return null;
  if (createdAt.isBefore(kTvPostedDateSince)) return null;
  final at = createdAt.toUtc().add(_tashkentOffset);
  final today = now.toUtc().add(_tashkentOffset);
  String two(int x) => x.toString().padLeft(2, '0');
  final sameDay =
      at.year == today.year && at.month == today.month && at.day == today.day;
  if (sameDay) return '$todayWord, ${two(at.hour)}:${two(at.minute)}';
  return '${two(at.day)}.${two(at.month)}.${at.year}';
}
