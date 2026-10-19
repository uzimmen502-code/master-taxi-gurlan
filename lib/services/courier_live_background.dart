// Курьернинг жонли нуқтасини ФОНДА ҳам ёзиш (S6, фон режими): иловани ёпиб/ўчириб қўйса ҳам мижоз ва ресторан
// эгаси курьерни кузатаверади. Алоҳида хизмат қурилмайди (43-қоида) — ҳайдовчилар учун ишлаб турган
// `BackgroundGpsService` (foreground service, type=location) шу ишни ҳам бажаради; бу файл — иловадаги
// фаол буюртмалар рўйхати (`SharedPreferences`) ва соф қоидалар (тестланади).
//
// Оқим: курьернинг фаол буюртма карточкаси `register` қилади → хизмат ишга тушади → ҳар 20 с да рўйхатдаги
// буюртмалар учун `order_courier_live/{orderId}` ёзилади (қоида: `CourierTracking.shouldPublish`, ёзиш
// ҳуқуқи — `firestore.rules`) → карточка йўқолса (`unregister`) рўйхатдан чиқади, рўйхат ва «онлайн»
// бўш бўлса хизмат ўзи тўхтайди.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'background_gps_service.dart';

/// Фонда ёзиладиган битта буюртма.
class CourierLiveEntry {
  const CourierLiveEntry({required this.orderId, required this.courierId});

  final String orderId;
  final String courierId;

  String encode() => '$orderId|$courierId';

  @override
  bool operator ==(Object other) => other is CourierLiveEntry && other.orderId == orderId && other.courierId == courierId;

  @override
  int get hashCode => Object.hash(orderId, courierId);
}

abstract final class CourierLiveBackground {
  /// Рўйхат калити (`SharedPreferences`, `List<String>` — «orderId|courierId»).
  static const prefsKey = 'courier_live_orders';

  /// Хизматнинг охирги ёзув вақти (epoch ms): илова хизмат ишлаётганини билсин ва қўш ёзмасин.
  static const heartbeatKey = 'courier_live_hb';

  /// Хизмат шунча вақт ичида ёзган бўлса, фонни «тирик» деб ҳисоблаймиз (кузатув эскириш чегараси билан бир хил).
  static const heartbeatFresh = Duration(seconds: 90);

  /// Рўйхатни ўқиш: бузилган/такрорий/бўш қаторлар ташланади.
  static List<CourierLiveEntry> parse(List<String>? raw) {
    final out = <CourierLiveEntry>[];
    for (final s in raw ?? const <String>[]) {
      final i = s.indexOf('|');
      if (i <= 0 || i == s.length - 1) continue;
      final e = CourierLiveEntry(orderId: s.substring(0, i), courierId: s.substring(i + 1));
      if (!out.contains(e)) out.add(e);
    }
    return out;
  }

  static List<String> add(List<String>? raw, CourierLiveEntry e) {
    final cur = parse(raw);
    if (!cur.contains(e)) cur.add(e);
    return cur.map((x) => x.encode()).toList();
  }

  static List<String> remove(List<String>? raw, String orderId) =>
      parse(raw).where((x) => x.orderId != orderId).map((x) => x.encode()).toList();

  /// Хизмат фонда ёзиб турибдими (охирги ёзув янги).
  static bool isFresh(int? heartbeatMs, DateTime now) {
    if (heartbeatMs == null) return false;
    final age = now.millisecondsSinceEpoch - heartbeatMs;
    return age >= 0 && age <= heartbeatFresh.inMilliseconds;
  }

  /// Фон хизмати фақат Android ўрнатилган иловада (веб/тест/iOS'да — илова ичидаги оқим).
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Карточка кўрингач: буюртмани рўйхатга олиб, хизматни ишга туширади. Хато (рухсат, канал) асосий ишни
  /// тўхтатмайди — илова ичидаги оқим барибир ёзади.
  static Future<void> register(String orderId, String courierId) async {
    if (!supported) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(prefsKey, add(prefs.getStringList(prefsKey), CourierLiveEntry(orderId: orderId, courierId: courierId)));
      await BackgroundGpsService.start();
    } catch (_) {}
  }

  /// Карточка йўқолгач: рўйхатдан чиқаради; хизмат рўйхат бўш (ва ҳайдовчи онлайн эмас) бўлса ўзи тўхтайди.
  static Future<void> unregister(String orderId) async {
    if (!supported) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(prefsKey, remove(prefs.getStringList(prefsKey), orderId));
    } catch (_) {}
  }

  /// Илова ичидаги ёзувчи фонга ишонса бўладими.
  static Future<bool> serviceCovers({DateTime Function()? clock}) async {
    if (!supported) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return isFresh(prefs.getInt(heartbeatKey), (clock ?? DateTime.now)());
    } catch (_) {
      return false;
    }
  }
}
