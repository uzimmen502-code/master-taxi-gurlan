import 'package:shared_preferences/shared_preferences.dart';

import '../../../models/relative_event.dart';
import '../../../models/relative_person.dart';
import '../../../services/notification_service.dart';

/// Qarindosh tug'ilgan kunlari va muhim sanalar uchun OS bildirishnomalarini
/// rejalashtiradi. Har sync'da eski rejalashtirilganlar bekor qilinib, joriy
/// ma'lumotlardan qaytadan rejalashtiriladi (ilova ochilganda chaqiriladi).
class RelativeReminderScheduler {
  static const _prefsKey = 'relative_reminder_ids';
  static const _notifyHour = 9; // 09:00 da eslatma

  Future<void> sync({
    required List<RelativePerson> people,
    required List<RelativeEvent> events,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Eski rejani tozalash.
    final old = prefs.getStringList(_prefsKey) ?? const [];
    for (final raw in old) {
      final id = int.tryParse(raw);
      if (id != null) await NotificationService.instance.cancelReminder(id);
    }

    final newIds = <int>[];

    Future<void> add(
        String key, String title, String body, DateTime day) async {
      final base = key.hashCode & 0x3FFFFFFF;
      final dayOf = DateTime(day.year, day.month, day.day, _notifyHour);
      final dayBefore = dayOf.subtract(const Duration(days: 1));
      final idDayOf = base * 2;
      final idDayBefore = base * 2 + 1;
      await NotificationService.instance.scheduleReminder(
        id: idDayOf,
        title: title,
        body: body,
        when: dayOf,
      );
      await NotificationService.instance.scheduleReminder(
        id: idDayBefore,
        title: 'Эртага: $title',
        body: body,
        when: dayBefore,
      );
      newIds.add(idDayOf);
      newIds.add(idDayBefore);
    }

    for (final p in people) {
      final nb = p.nextBirthday;
      if (nb == null) continue;
      final turning = (p.age ?? 0) + 1;
      await add(
        'bd_${p.id}',
        '🎂 ${p.fullName}',
        'Туғилган куни — $turning ёшга тўлади',
        nb,
      );
    }

    for (final e in events) {
      if (e.isPast) continue;
      final body = [
        if (e.place.isNotEmpty) e.place,
        if (e.note.isNotEmpty) e.note,
      ].join(' · ');
      await add(
        'ev_${e.id}',
        '${e.type.emoji} ${e.title}',
        body.isEmpty ? 'Муҳим сана' : body,
        e.nextOccurrence,
      );
    }

    await prefs.setStringList(
      _prefsKey,
      newIds.map((e) => e.toString()).toList(),
    );
  }
}
