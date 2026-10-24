import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart' show phonesMatch;
import '../models/tv_clip.dart';

/// «Кун янгиликлари» табидаги ўқилмаганлик нуқтаси (эга қарори, 2026-10-24).
///
/// Қурилмада сақланади (серверга ёзув йўқ): бошқа қурилмада ёки қайта ўрнатгандан кейин нуқта яна чиқиши
/// мумкин — онгли чекланиш. Ҳисоб бўйича синхрон керак бўлса, кейин алоҳида қарор.

/// Кўриниши мумкин энг сўнгги янгилик вақти: фаол, ўйнатиладиган, муддати тугамаган, ўзимники эмас.
/// Қайтарилган вақт — СЕРВЕР вақти (`createdAt`), телефон соати эмас.
DateTime? newestVisibleNewsAt(
  Iterable<TvClip> clips, {
  required String mePhone,
  required DateTime now,
}) {
  DateTime? best;
  for (final c in clips) {
    if (!c.isNews || !c.isActive || !c.isPlayable) continue;
    final exp = c.expiresAt;
    if (exp != null && !exp.isAfter(now)) continue;
    if (mePhone.isNotEmpty && phonesMatch(c.ownerPhone, mePhone)) continue;
    final at = c.createdAt;
    if (at == null) continue;
    if (best == null || at.isAfter(best)) best = at;
  }
  return best;
}

/// Нуқта керакми: янгилик бор ва у охирги кўрилгандан кейин чиққан (ёки ҳали ҳеч қачон очилмаган).
bool tvNewsHasUnread({required DateTime? latest, required DateTime? seen}) =>
    latest != null && (seen == null || latest.isAfter(seen));

/// «Охирги кўрилган янгилик вақти» — SharedPreferences. Фақат олдинга силжийди (орқага қайтмайди).
class TvNewsSeenStore {
  const TvNewsSeenStore._();

  static const key = 'tv_news_seen_at_ms';

  static Future<DateTime?> read() async {
    try {
      final ms = (await SharedPreferences.getInstance()).getInt(key);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    } catch (e) {
      debugPrint('[TvNewsSeenStore] read: $e');
      return null;
    }
  }

  static Future<void> markSeen(DateTime at) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final old = prefs.getInt(key);
      final ms = at.millisecondsSinceEpoch;
      if (old == null || ms > old) await prefs.setInt(key, ms);
    } catch (e) {
      debugPrint('[TvNewsSeenStore] write: $e');
    }
  }
}
