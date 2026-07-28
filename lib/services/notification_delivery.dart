import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/utils/formatters.dart';
import 'push_navigation.dart';

/// Firestore `notifications` ва FCM учун умумий local push кўрсатish.
class NotificationDelivery {
  NotificationDelivery._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  static Future<void> ensureInitialized() async {
    if (_inited || kIsWeb) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (response) {
        PushNavigation.handlePayload(response.payload);
      },
    );

    const alarmSound = RawResourceAndroidNotificationSound('incoming_ring');
    final alarmVibrate = Int64List.fromList([0, 800, 400, 800, 400, 1200]);

    final channels = [
      AndroidNotificationChannel(
        'intercity_driver_alarm',
        'Ҳайдовчи — янги брон',
        description: 'Қўнғироқга ўхшаш оғоз (шахарлараро)',
        importance: Importance.max,
        playSound: true,
        sound: alarmSound,
        enableVibration: true,
        vibrationPattern: alarmVibrate,
      ),
      AndroidNotificationChannel(
        'incoming_ride',
        'Янги брон сўрови',
        description: 'Шаҳарлараро / маршрут — юқори аҳамият',
        importance: Importance.max,
        playSound: true,
        sound: alarmSound,
        enableVibration: true,
      ),
      AndroidNotificationChannel(
        'courier_arrival_alarm',
        'Курьер етиб келди',
        description: 'Курьер манзилга етиб келганда қўнғироқли огоҳлантириш',
        importance: Importance.max,
        playSound: true,
        sound: alarmSound,
        enableVibration: true,
        vibrationPattern: alarmVibrate,
      ),
      const AndroidNotificationChannel(
        'taxi_channel',
        'Такси хабарлари',
        importance: Importance.high,
      ),
      const AndroidNotificationChannel(
        'order_channel',
        'Буюртма хабарлари',
        importance: Importance.high,
      ),
    ];

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    for (final ch in channels) {
      await androidPlugin?.createNotificationChannel(ch);
    }
    _inited = true;
  }

  /// Ҳайдовчига янги брон — қўнғироқ канали.
  static bool isDriverBookingAlert(String type) {
    return type == 'intercity_booking_pending' ||
        type == 'intercity_booking' ||
        type == 'marshrut_request';
  }

  /// Баланд приоритетли огоҳлантиришлар (heads-up) — fullScreenIntent йўқ
  /// (Play: USE_FULL_SCREEN_INTENT faqat alarm/call core apps).
  static bool isRingAlert(String type) {
    return isDriverBookingAlert(type) || type == 'courier_arrived';
  }

  static String channelForType(String type) {
    if (type == 'courier_arrived') {
      return 'courier_arrival_alarm';
    }
    if (isDriverBookingAlert(type)) {
      return 'intercity_driver_alarm';
    }
    const passengerIntercity = {
      'intercity_pickup_request',
      'intercity_seats_update',
      'intercity_departure_reminder',
      'intercity_trip_completed',
      'intercity_booking_cancelled',
    };
    if (passengerIntercity.contains(type) ||
        type.startsWith('intercity') && !isDriverBookingAlert(type)) {
      return 'taxi_channel';
    }
    if (type == 'trip_accepted') {
      return 'taxi_channel';
    }
    if (type == 'ad_published' ||
        type == 'ad_moderation' ||
        type == 'sell_offer' ||
        type == 'identity') {
      return 'order_channel';
    }
    return 'order_channel';
  }

  static Future<void> show({
    required String title,
    required String body,
    required String type,
    Map<String, String>? navigationData,
  }) async {
    if (kIsWeb) return;
    await ensureInitialized();
    final channelId = channelForType(type);
    final isAlarm = isRingAlert(type);
    final alarmChannelName =
        type == 'courier_arrived' ? 'Курьер етиб келди' : 'Ҳайдовчи — янги брон';
    const alarmSound = RawResourceAndroidNotificationSound('incoming_ring');
    final nav = PushNavigation.enrichFcmData({
      'type': type,
      if (navigationData != null) ...navigationData,
    });
    final payload = PushNavigation.encodePayload(nav);
    try {
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            isAlarm ? alarmChannelName : 'Хабар',
            channelDescription: isAlarm ? 'Қўнғироқ оғози' : null,
            importance: isAlarm ? Importance.max : Importance.high,
            priority: isAlarm ? Priority.max : Priority.high,
            playSound: true,
            sound: isAlarm ? alarmSound : null,
            enableVibration: true,
            vibrationPattern: isAlarm
                ? Int64List.fromList([0, 800, 400, 800, 400, 1200])
                : null,
            fullScreenIntent: false,
            category: AndroidNotificationCategory.message,
            visibility: NotificationVisibility.public,
            icon: '@mipmap/ic_launcher',
            ongoing: false,
            autoCancel: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
        payload: payload,
      );
    } catch (_) {}
  }

  /// Firestore `notifications` ёзуви (targetPhone — каноник рақамлар).
  static Future<DocumentReference<Map<String, dynamic>>> write({
    required FirebaseFirestore db,
    required String targetPhoneRaw,
    required String title,
    required String body,
    required String type,
    Map<String, dynamic> extra = const {},
  }) async {
    return db.collection('notifications').add({
      'targetPhone': notificationTargetPhone(targetPhoneRaw),
      'title': title,
      'body': body,
      'sent': false,
      'type': type,
      if (type == 'intercity_booking_pending') 'priority': 'high',
      'createdAt': FieldValue.serverTimestamp(),
      ...extra,
    });
  }
}
