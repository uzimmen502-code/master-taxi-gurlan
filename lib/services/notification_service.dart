import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

  Future<void> setup() async {
    if (_initialized) return;
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: (_) => _onTapped?.call(),
    );
    _initialized = true;
  }

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
