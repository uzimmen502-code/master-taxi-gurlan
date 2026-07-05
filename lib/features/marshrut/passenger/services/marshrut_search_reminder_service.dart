import 'package:shared_preferences/shared_preferences.dart';

import '../../../../services/notification_service.dart';

/// Marshrut qidiruv eslatmasi — yo'lovchi haydovchi topilmasa keyinroq eslatish.
class MarshrutSearchReminder {
  const MarshrutSearchReminder({
    required this.fromMfy,
    required this.toMfy,
    required this.scheduledAt,
  });

  final String fromMfy;
  final String toMfy;
  final DateTime scheduledAt;

  bool get isActive => scheduledAt.isAfter(DateTime.now());

  static MarshrutSearchReminder? decode(String raw) {
    final parts = raw.split('\u0001');
    if (parts.length != 3) return null;
    final from = parts[0].trim();
    final to = parts[1].trim();
    final when = DateTime.tryParse(parts[2]);
    if (from.isEmpty || to.isEmpty || when == null) return null;
    return MarshrutSearchReminder(fromMfy: from, toMfy: to, scheduledAt: when);
  }
}

class MarshrutSearchReminderService {
  MarshrutSearchReminderService._();
  static final MarshrutSearchReminderService instance =
      MarshrutSearchReminderService._();

  static const _prefsKey = 'marshrut_search_reminder_v1';

  int _notificationId(String from, String to) =>
      'marshrut|$from|$to'.hashCode & 0x7FFFFFFF;

  Future<MarshrutSearchReminder?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return null;
    final reminder = MarshrutSearchReminder.decode(raw);
    if (reminder == null || !reminder.isActive) {
      await clear();
      return null;
    }
    return reminder;
  }

  Future<void> schedule({
    required String fromMfy,
    required String toMfy,
    required Duration delay,
    required String title,
    required String body,
  }) async {
    final from = fromMfy.trim();
    final to = toMfy.trim();
    if (from.isEmpty || to.isEmpty) return;

    final when = DateTime.now().add(delay);
    final id = _notificationId(from, to);
    await NotificationService.instance.scheduleReminder(
      id: id,
      title: title,
      body: body,
      when: when,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      '$from\u0001$to\u0001${when.toIso8601String()}',
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null) {
      final reminder = MarshrutSearchReminder.decode(raw);
      if (reminder != null) {
        await NotificationService.instance.cancelReminder(
          _notificationId(reminder.fromMfy, reminder.toMfy),
        );
      }
    }
    await prefs.remove(_prefsKey);
  }

  bool matchesRoute(MarshrutSearchReminder? reminder, String from, String to) {
    if (reminder == null) return false;
    return reminder.fromMfy == from.trim() && reminder.toMfy == to.trim();
  }
}
