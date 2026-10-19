import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';
import '../features/restaurants/domain/courier_tracking.dart';
import 'courier_live_background.dart';
// ── Background GPS Service ──
// Ҳайдовчи иловани ёпиб қўйса ҳам GPS ишлайди

class BackgroundGpsService {
  static final _service = FlutterBackgroundService();

  /// Foreground service notification канали. configure'даги
  /// `notificationChannelId` билан АЙНАН бир хил бўлиши шарт.
  static const String _channelId = 'gps_channel';

  // ── Инициализация ──
  static Future<void> init() async {
    // ⚠️ Канал АВВАЛ яратилиши шарт: акс ҳолда foreground service
    // startForeground'да "invalid channel" → CannotPostForegroundService
    // NotificationException бериб иловани йиқитади (Android 12+/targetSdk 34+).
    await _ensureChannel();
    await _service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart:         onStart,
        autoStart:       false,
        isForegroundMode: true,
        notificationChannelId: 'gps_channel',
        initialNotificationTitle: 'AVA',
        initialNotificationContent: '🟢 GPS фаол — йўловчиларга кўринасиз',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );
  }

  /// `gps_channel` нотификация каналини яратади (idempotent — қайта чақириш
  /// хавфсиз). Importance.low — товуш/вибрациясиз, доимий GPS бельгиси учун.
  static Future<void> _ensureChannel() async {
    const channel = AndroidNotificationChannel(
      _channelId,
      'GPS фон хизмати',
      description: 'Ҳайдовчи онлайн пайтида GPS жойлашувини юборади',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
    );
    try {
      await FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    } catch (_) {}
  }

  // ── Сервисни бошлаш ──
  static Future<void> start() async {
    // Канал яратилганлигига кафолат (init чақирилмаган бўлса ҳам).
    await _ensureChannel();
    final running = await _service.isRunning();
    if (!running) await _service.startService();
  }

  // ── Сервисни тўхтатиш ──
  static Future<void> stop() async {
    // Курьер фаол буюртмани кузатувга ёзаётган бўлса хизмат ишлашда давом этади (ҳайдовчи оффлайн бўлса ҳам).
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      if (CourierLiveBackground.parse(prefs.getStringList(CourierLiveBackground.prefsKey)).isNotEmpty) return;
    } catch (_) {}
    final running = await _service.isRunning();
    if (running) _service.invoke('stop');
  }

  static Future<bool> isRunning() => _service.isRunning();
}

// ── iOS background handler ──
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

// ── Асосий background логика ──
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  if (service is AndroidServiceInstance) {
    service.on('stop').listen((_) => service.stopSelf());
    service.on('setAsForeground').listen((_) =>
        service.setAsForegroundService());
    service.on('setAsBackground').listen((_) =>
        service.setAsBackgroundService());
  }

  // SharedPreferences дан ҳайдовчи маълумотлари
  final prefs    = await SharedPreferences.getInstance();
  final phone    = prefs.getString('user_phone')  ?? '';
  final driverId = phone.replaceAll(RegExp(r'[^\d]'), '');

  // Хизмат икки иш учун: ҳайдовчи онлайн (drivers/{phone}) ва курьернинг фаол буюртмалари
  // (order_courier_live/{orderId}). Иккиси ҳам йўқ бўлса — тўхтайди.
  final startLive = CourierLiveBackground.parse(prefs.getStringList(CourierLiveBackground.prefsKey));
  if (driverId.isEmpty && startLive.isEmpty) {
    if (service is AndroidServiceInstance) service.stopSelf();
    return;
  }

  final db = FirebaseFirestore.instance;

  // Курьер ёзувлари учун охирги ёзилган нуқта (orderId бўйича) — ортиқча ёзмаслик (36-қоида).
  final lastAt  = <String, DateTime>{};
  final lastPos = <String, List<double>>{};

  // GPS позицияни ҳар 20 секундда янгилаш
  Timer.periodic(const Duration(seconds: 20), (timer) async {
    // Асосий изолятда ўзгарган рўйхат/ҳолатни кўриш учун қайта ўқиймиз.
    try { await prefs.reload(); } catch (_) {}
    final isOnline = prefs.getBool('driver_online') ?? false;
    final live = CourierLiveBackground.parse(prefs.getStringList(CourierLiveBackground.prefsKey));
    // Онлайн эмас ва кузатиладиган буюртма йўқ бўлса — тўхтатиш
    final driverActive = isOnline && driverId.isNotEmpty;
    if (!driverActive && live.isEmpty) {
      timer.cancel();
      if (service is AndroidServiceInstance) service.stopSelf();
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      if (driverActive) {
        await db.collection('drivers').doc(driverId).update({
          'lat':       pos.latitude,
          'lng':       pos.longitude,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // Курьер: ҳар бир фаол буюртма учун жонли нуқта (рухсат ва фаоллик — firestore.rules).
      final now = DateTime.now();
      var wrote = false;
      for (final e in live) {
        final last = lastPos[e.orderId];
        if (!CourierTracking.shouldPublish(
          now: now,
          lat: pos.latitude,
          lng: pos.longitude,
          lastAt: lastAt[e.orderId],
          lastLat: last?[0],
          lastLng: last?[1],
        )) {
          continue;
        }
        try {
          await db.collection('order_courier_live').doc(e.orderId).set({
            'orderId':   e.orderId,
            'courierId': e.courierId,
            'lat':       pos.latitude,
            'lng':       pos.longitude,
            if (pos.heading >= 0 && pos.heading <= 360) 'heading': pos.heading,
            if (pos.speed >= 0 && pos.speed <= 100) 'speed': pos.speed,
            if (pos.accuracy >= 0) 'accuracy': pos.accuracy,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          lastAt[e.orderId]  = now;
          lastPos[e.orderId] = [pos.latitude, pos.longitude];
          wrote = true;
        } catch (_) {
          // Рухсат/тармоқ: кейинги айланишда қайта уриниш.
        }
      }
      if (wrote) {
        await prefs.setInt(CourierLiveBackground.heartbeatKey, now.millisecondsSinceEpoch);
      }

      // Notification янгилаш
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'AVA',
          content: driverActive
              ? '🟢 GPS фаол — ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}'
              : '🟢 Етказиб бериш кузатуви фаол',
        );
      }
    } catch (_) {}
  });
}