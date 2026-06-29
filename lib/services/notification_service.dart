import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Lokal push (Android) bildirishnomalarini ko'rsatish uchun yagona joy.
///
/// Singleton, chunki `flutter_local_notifications` plugin ham global. Hozircha
/// faqat marshrut haydovchi panelida ishlatilمoqda — keyinroq boshqa kontekstlar
/// qo'shilsa, callback yangilanadi.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  VoidCallback? _onTapped;
  bool _initialized = false;

  /// Eslatmalar uchun kanal (qarindosh tug'ilgan kuni / muhim sanalar).
  static const reminderChannelId = 'relative_reminders';

  Future<void> setup() async {
    if (_initialized) return;

    // Vaqt zonasi (zonedSchedule uchun) — ilova hududi: O'zbekiston (UTC+5).
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Tashkent'));
    } catch (_) {
      // fallback: tz.local UTC bo'lib qoladi
    }

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: (_) => _onTapped?.call(),
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    const incomingRideChannel = AndroidNotificationChannel(
      'incoming_ride',
      'Янги буюртма',
      description: 'Маршрут ҳайдовчисига келган янги сўровлар',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    const reminderChannel = AndroidNotificationChannel(
      reminderChannelId,
      'Эслатмалар',
      description: 'Қариндошлар туғилган кунлари ва муҳим саналар',
      importance: Importance.high,
    );
    await android?.createNotificationChannel(incomingRideChannel);
    await android?.createNotificationChannel(reminderChannel);
    await android?.requestNotificationsPermission();

    _initialized = true;
  }

  /// Belgilangan vaqtga eslatma rejalashtiradi (o'tmishdagi vaqt — e'tiborsiz).
  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    if (when.isBefore(DateTime.now())) return;
    final scheduled = tz.TZDateTime.from(when, tz.local);
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          reminderChannelId,
          'Эслатмалар',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  Future<void> cancelReminder(int id) => _plugin.cancel(id);

  /// Bildirishnoma bosilganda chaqiriladigan callback. Controller `init()`'da
  /// o'rnatadi, `dispose()`'da tozalaydi.
  void setOnTapped(VoidCallback? callback) {
    _onTapped = callback;
  }

  Future<void> showIncomingMarshrutRide({
    required String pickupMfy,
    required String dropoffMfy,
  }) async {
    await _plugin.show(
      DateTime.now().millisecond,
      '🚐 Янги буюртма!',
      '$pickupMfy → $dropoffMfy',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'incoming_ride',
          'Янги буюртма',
          importance: Importance.max,
          priority: Priority.max,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.call,
        ),
      ),
    );
  }
}
