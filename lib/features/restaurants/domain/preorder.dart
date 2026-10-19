// Олдиндан буюртма (S4b, D-REST-35; docs/kafe_restoran_taklifi_uz.md §10.1).
//
// Эга қарори (2026-10-19): камида 60 дақиқа олдин, кўпи билан 7 кун, ресторан профилида «олдиндан буюртма
// оламан» белгиси, иш вақти ШУ вақт бўйича. Ҳақиқий текширув — серверда (`functions/restaurant_preorder.js`,
// `placeRestaurantOrder`); бу ерда фақат тугмани ўчириш ва аниқ хато матнини кўрсатиш учун шу қоиданинг
// нусхаси (мослик `preorder_test.dart` да серверга қарши қулфланган).

import 'restaurant_models.dart';

abstract final class Preorder {
  /// Серверда `MIN_LEAD_MIN` / `MAX_DAYS`.
  static const minLeadMin = 60;
  static const maxDays = 7;

  /// Вақт танлаш қадами (дақиқа) — мижозга қулай ва ресторанга ўқилувчан.
  static const stepMin = 15;

  /// Хато калитлари → `restaurants_preorder_err_<калит>` (3 тилда).
  static const errSoon = 'soon';
  static const errFar = 'far';
  static const errClosed = 'closed_at_time';
  static const errPaused = 'paused';

  /// Танланган вақт ярайдими: `null` — ҳа; акс ҳолда хато калити. Сервер қоидаси билан бир хил тартиб:
  /// белги → оралиқ (60 дақиқа…7 кун) → пауза → ишлаш вақти (БАЖАРИЛИШ вақтида).
  static String? check({required DateTime now, required DateTime scheduled, required Restaurant restaurant}) {
    final lead = scheduled.difference(now);
    if (lead < const Duration(minutes: minLeadMin)) return errSoon;
    if (lead > const Duration(days: maxDays)) return errFar;
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
  static List<DateTime> days(DateTime now) => [
        for (var i = 0; i <= maxDays; i++) DateTime(now.year, now.month, now.day + i),
      ];

  /// Кўрсатиш: `21.10 19:00` (қурилма вақти; ҳафта куни ёзилмайди — тилга боғлиқ эмас).
  static String format(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  /// Кун ва вақтдан бирлашган [DateTime].
  static DateTime combine(DateTime day, int hour, int minute) => DateTime(day.year, day.month, day.day, hour, minute);
}
