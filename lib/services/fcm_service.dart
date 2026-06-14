import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/formatters.dart';
import '../firebase_options.dart';
import 'arrival_ringer.dart';
import 'notification_delivery.dart';
import 'push_navigation.dart';

/// Background FCM — илова ёпиқ/фонда ҳам local notification (#16).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kIsWeb) return;
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await NotificationDelivery.ensureInitialized();
  final n = message.notification;
  final type = message.data['type'] as String? ?? '';
  final nav = PushNavigation.enrichFcmData(
    message.data.map((k, v) => MapEntry(k, v?.toString() ?? '')),
  );
  if (n != null) {
    await NotificationDelivery.show(
      title: n.title ?? '',
      body: n.body ?? '',
      type: type.isNotEmpty ? type : 'intercity_booking_pending',
      navigationData: nav,
    );
    return;
  }
  final title = message.data['title'] as String? ?? 'Хабар';
  final body = message.data['body'] as String? ?? '';
  await NotificationDelivery.show(
    title: title,
    body: body,
    type: type,
    navigationData: nav,
  );
}

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final _messaging = FirebaseMessaging.instance;
  final _db = FirebaseFirestore.instance;

  final List<StreamSubscription<QuerySnapshot>> _notifSubs = [];

  String _userPhone = '';

  Future<void> init() async {
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) return;

    await NotificationDelivery.ensureInitialized();
    await _saveToken();
    _messaging.onTokenRefresh.listen(_onTokenRefresh);
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpened);
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _onMessageOpened(initial);
  }

  /// #9 — барча телефон alias'лари бўйича `notifications` кузатиш.
  Future<void> startListeners() async {
    final prefs = await SharedPreferences.getInstance();
    _userPhone = prefs.getString('user_phone') ?? '';
    if (_userPhone.isEmpty) return;

    final aliases = phoneAliases(_userPhone);
    if (aliases.isEmpty) return;

    stopListeners();

    for (final alias in aliases) {
      final sub = _db
          .collection('notifications')
          .where('targetPhone', isEqualTo: alias)
          .where('sent', isEqualTo: false)
          .snapshots()
          .listen((snap) async {
        for (final change in snap.docChanges) {
          if (change.type != DocumentChangeType.added) continue;
          final data = change.doc.data() as Map<String, dynamic>;
          final target = data['targetPhone'] as String? ?? '';
          if (!phonesMatch(target, _userPhone)) continue;

          final type = data['type'] as String? ?? '';
          final title = data['title'] as String? ?? '';
          final body = data['body'] as String? ?? '';
          final taxiType = data['taxiType'] as String? ?? 'local';
          final prefs = await SharedPreferences.getInstance();
          final userRole = prefs.getString('user_role') ?? 'user';

          if (type == 'driver_request_approved' &&
              userRole != 'driver') {
            await change.doc.reference.update({'sent': true});
            continue;
          }

          if (type == 'courier_arrived') {
            ArrivalRinger.instance.start();
          }

          final nav = PushNavigation.enrichFcmData({
            'type': type,
            if (data['screen'] != null) 'screen': '${data['screen']}',
            if (data['tab'] != null) 'tab': '${data['tab']}',
            if (data['bookingId'] != null) 'bookingId': '${data['bookingId']}',
            if (taxiType.isNotEmpty) 'taxiType': taxiType,
          });
          await NotificationDelivery.show(
            title: title,
            body: body,
            type: type,
            navigationData: nav,
          );
          try {
            await change.doc.reference.update({'sent': true});
          } catch (_) {}
        }
      });
      _notifSubs.add(sub);
    }
  }

  Future<void> _saveToken([String? token]) async {
    final t = token ?? await _messaging.getToken();
    if (t == null) return;
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone') ?? '';
    if (phone.isEmpty) return;
    final uid = canonicalPhoneId(phone);
    try {
      await prefs.setString('fcm_token', t);
      await _db.collection('users').doc(uid).set({
        'phone': phone,
        'phoneDigits': uid,
        // role intentionally omitted — only admin CF / rules change role
        'fcmToken': t,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> _onTokenRefresh(String token) => _saveToken(token);

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    final n = message.notification;
    final type = message.data['type'] as String? ?? '';
    final nav = PushNavigation.enrichFcmData(
      PushNavigation.dataFromMessage(message),
    );
    if (type == 'courier_arrived') {
      // 7с/10с×3 ритмда қўнғироқ (foreground).
      ArrivalRinger.instance.start();
    }
    if (n != null) {
      await NotificationDelivery.show(
        title: n.title ?? '',
        body: n.body ?? '',
        type: type.isNotEmpty ? type : 'order',
        navigationData: nav,
      );
    } else if (type.isNotEmpty) {
      await NotificationDelivery.show(
        title: message.data['title'] as String? ?? 'Хабар',
        body: message.data['body'] as String? ?? '',
        type: type,
        navigationData: nav,
      );
    }
  }

  void _onMessageOpened(RemoteMessage message) {
    PushNavigation.handleData(
      PushNavigation.enrichFcmData(PushNavigation.dataFromMessage(message)),
    );
  }

  Future<void> refreshToken() => _saveToken();

  void stopListeners() {
    for (final s in _notifSubs) {
      s.cancel();
    }
    _notifSubs.clear();
  }
}
