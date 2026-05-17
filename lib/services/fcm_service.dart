import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Background handler
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final _messaging         = FirebaseMessaging.instance;
  final _db                = FirebaseFirestore.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  // Firestore listeners (буюртма/сафар — Cloud Functions FCM + Админ чати)
  StreamSubscription<QuerySnapshot>? _notifSub;

  String _userPhone = '';

  // ── Инициализация ──
  Future<void> init() async {
    // Вебда isolate background handler ишламайди; рўйхатлаш ba'zi muhitlarda xato beradi.
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }

    final settings = await _messaging.requestPermission(
        alert: true, badge: true, sound: true);
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    await _initLocalNotifications();
    await _saveToken();
    _messaging.onTokenRefresh.listen(_onTokenRefresh);
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpened);
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _onMessageOpened(initial);
  }

  // ── Firestore listeners — Cloud Functions olmiga ──
  Future<void> startListeners() async {
    final prefs = await SharedPreferences.getInstance();
    _userPhone  = prefs.getString('user_phone') ?? '';

    if (_userPhone.isEmpty) return;

    // Notifications коллекцияси — Firestore orqали push
    _notifSub = _db.collection('notifications')
        .where('targetPhone', isEqualTo: _userPhone)
        .where('sent', isEqualTo: false)
        .snapshots()
        .listen((snap) async {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data  = change.doc.data() as Map<String, dynamic>;
        final title = data['title'] as String? ?? '';
        final body  = data['body']  as String? ?? '';
        await _showNotification(title, body, 'order_channel');
        // Ўқилди деб белгилаш
        try {
          await change.doc.reference.update({'sent': true});
        } catch (_) {}
      }
    });
  }

  // ── Local notifications ──
  Future<void> _initLocalNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios     = DarwinInitializationSettings();
    await _localNotifications.initialize(
        const InitializationSettings(android: android, iOS: ios));

    const taxiChannel = AndroidNotificationChannel(
        'taxi_channel', 'Такси хабарлари',
        description: 'Такси сафарлари ҳақида хабарлар',
        importance: Importance.high);
    const orderChannel = AndroidNotificationChannel(
        'order_channel', 'Буюртма хабарлари',
        description: 'Нон ва овқат буюртмалари ҳақида хабарлар',
        importance: Importance.high);

    final plugin = _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await plugin?.createNotificationChannel(taxiChannel);
    await plugin?.createNotificationChannel(orderChannel);
  }

  Future<void> _showNotification(
      String title, String body, String channelId) async {
    try {
      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title, body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelId == 'taxi_channel'
                ? 'Такси хабарлари' : 'Буюртма хабарлари',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(
              presentAlert: true, presentBadge: true, presentSound: true),
        ),
      );
    } catch (_) {}
  }

  // ── FCM Token ──
  Future<void> _saveToken([String? token]) async {
    final t = token ?? await _messaging.getToken();
    if (t == null) return;
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    final role  = prefs.getString('user_role')  ?? 'user';
    if (phone.isEmpty) return;
    final uid = phone.replaceAll(RegExp(r'[^\d]'), '');
    try {
      await prefs.setString('fcm_token', t);
      await _db.collection('users').doc(uid).set({
        'phone': phone, 'role': role, 'fcmToken': t,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _onTokenRefresh(String token) => _saveToken(token);

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final n = message.notification;
    if (n == null) return;
    final channelId = message.data['type'] == 'trip_accepted'
        ? 'taxi_channel' : 'order_channel';
    await _showNotification(n.title ?? '', n.body ?? '', channelId);
  }

  void _onMessageOpened(RemoteMessage message) {}

  Future<void> refreshToken() => _saveToken();

  void stopListeners() {
    _notifSub?.cancel();
  }
}