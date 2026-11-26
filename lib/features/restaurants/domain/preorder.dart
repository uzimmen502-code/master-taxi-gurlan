// Олдиндан буюртма (S4b, D-REST-35; docs/kafe_restoran_taklifi_uz.md §10.1).
//
// Эга қарори (2026-10-19): камида 60 дақиқа олдин, кўпи билан 7 кун, ресторан профилида «олдиндан буюртма
// оламан» белгиси, иш вақти ШУ вақт бўйича. Ҳақиқий текширув — серверда (`functions/restaurant_preorder.js`,
// `placeRestaurantOrder`); бу ерда фақат тугмани ўчириш ва аниқ хато матнини кўрсатиш учун шу қоиданинг
// нусхаси (мослик `preorder_test.dart` да серверга қарши қулфланган).

import 'restaurant_models.dart';

// Эга 2026-11-27: кўпи билан 14 кун (аввал 7); таом даражасида «Олдиндан буюртмага» (`preorderable`) ва «Камида неча
// кун олдин» (`preorderLeadDays` 0..14) — саватдаги таомларнинг энг каттаси бўйича энг эрта кун ([leadDaysOf]).

abstract final class Preorder {
  /// Серверда `MIN_LEAD_MIN` / `MAX_DAYS`.
  static const minLeadMin = 60;
  static const maxDays = 14;

  /// Таомнинг «камида неча кун олдин» чегараси (`preorderLeadDays`).
  static const maxLeadDays = 14;
  static const errLead = 'lead';

  /// Саватдаги таомлар учун энг катта «камида N кун олдин» (фақат `preorderable` таомлар); 0 — чеклов йўқ.
  static int leadDaysOf(Iterable<MenuItem> items) {
    var n = 0;
    for (final i in items) {
      if (i.preorderable && i.preorderLeadDays > n) n = i.preorderLeadDays;
    }
    return n > maxLeadDays ? maxLeadDays : n;
  }

  /// [leadDays] кун олдин — энг эрта календар куни (бугун + N, ярим тун).
  static DateTime earliestDay(DateTime now, int leadDays) => DateTime(now.year, now.month, now.day + leadDays);

  /// Вақт танлаш қадами (дақиқа) — мижозга қулай ва ресторанга ўқилувчан.
  static const stepMin = 15;

  /// Хато калитлари → `restaurants_preorder_err_<калит>` (3 тилда).
  static const errSoon = 'soon';
  static const errFar = 'far';
  static const errClosed = 'closed_at_time';
  static const errPaused = 'paused';

  /// Танланган вақт ярайдими: `null` — ҳа; акс ҳолда хато калити. Сервер қоидаси билан бир хил тартиб:
  /// белги → оралиқ (60 дақиқа…7 кун) → пауза → ишлаш вақти (БАЖАРИЛИШ вақтида).
  static String? check({
    required DateTime now,
    required DateTime scheduled,
    required Restaurant restaurant,
    int leadDays = 0,
  }) {
    final lead = scheduled.difference(now);
    if (lead < const Duration(minutes: minLeadMin)) return errSoon;
    if (lead > const Duration(days: maxDays)) return errFar;
    if (leadDays > 0 && scheduled.isBefore(earliestDay(now, leadDays))) return errLead;
    final paused = restaurant.pausedUntil;
    if (paused != null && paused.isAfter(scheduled)) return errPaused;
    if (!(restaurant.openingHours?.isOpenAt(scheduled) ?? true)) return errClosed;
    return null;
  }

  /// Бошланғич таклиф: ҳозирдан ~90 дақиқа кейин, [stepMin] га юқорига яхлитланган (тор оралиқдан чиқмайди).
  static DateTime suggest(DateTime now) {
    final t = now.add(const Duration(minutes: minLeadMin + 30));
    final rem = t.minute % stepMin;
    final rounded = rem == 0 ? t : t.add(Duration(minutes: stepMin - rem));
    return DateTime(rounded.year, rounded.month, rounded.day, rounded.hour, rounded.minute);
  }

  /// Танлаш мумкин кунлар (бугундан бошлаб [maxDays] кундан кейингисигача, ярим тундан).
  /// [leadDays] берилса — энг эрта кундан бошлаб.
  static List<DateTime> days(DateTime now, {int leadDays = 0}) => [
        for (var i = leadDays.clamp(0, maxDays); i <= maxDays; i++) DateTime(now.year, now.month, now.day + i),
      ];

  /// Танланган вақт энг эрта кундан олдин бўлса — энг эрта кунга (вақти сақланади); акс ҳолда ўзгармайди.
  static DateTime clampToLead(DateTime now, DateTime scheduled, int leadDays) {
    if (leadDays <= 0) return scheduled;
    final e = earliestDay(now, leadDays);
    if (!scheduled.isBefore(e)) return scheduled;
    final moved = combine(e, scheduled.hour, scheduled.minute);
    final limit = now.add(const Duration(days: maxDays));
    if (!moved.isAfter(limit)) return moved;
    // 14 кунлик чегарадан ошмасин: чегарага, [stepMin] га пастга яхлитланган.
    return DateTime(limit.year, limit.month, limit.day, limit.hour, limit.minute - limit.minute % stepMin);
  }

  /// Кўрсатиш: `21.10 19:00` (қурилма вақти; ҳафта куни ёзилмайди — тилга боғлиқ эмас).
  static String format(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  /// Кун ва вақтдан бирлашган [DateTime].
  static DateTime combine(DateTime day, int hour, int minute) => DateTime(day.year, day.month, day.day, hour, minute);
}
