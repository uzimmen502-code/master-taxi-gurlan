import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settlement_service.dart';

/// Settlement Ledger — Deferred (offline-lite) klient navbati.
///
/// Trip yakunida internet yo'q/xato bo'lib settlement online ochilmasa,
/// qaytim lokal navbatga (SharedPreferences) yoziladi. Internet qaytgach
/// `submitDeferredSettlement` CF orqali post qilinadi (idempotent: opId).
///
/// To'liq dizayn: docs/settlement_ledger_v1_uz.md (7-bo'lim)
class DeferredSettlementQueue {
  DeferredSettlementQueue._();

  static const String _key = 'deferred_settlements_v1';

  /// Poison guard: shuncha urinishdan keyin element tashlanadi.
  static const int _maxAttempts = 30;

  /// Bir vaqtda faqat bitta flush.
  static bool _flushing = false;

  /// Qaytimni navbatga qo'shadi (opId bo'yicha dedupe). Mavjud bo'lsa yangilamaydi.
  static Future<void> enqueue({
    required String passengerPhone,
    required String tripId,
    required String opId,
    required int settlementAmount,
  }) async {
    if (passengerPhone.isEmpty || tripId.isEmpty || opId.isEmpty) return;
    if (settlementAmount <= 0) return;
    final prefs = await SharedPreferences.getInstance();
    final items = _read(prefs);
    if (items.any((e) => e['opId'] == opId)) return; // dedupe
    items.add(<String, dynamic>{
      'opId': opId,
      'passengerPhone': passengerPhone,
      'tripId': tripId,
      'settlementAmount': settlementAmount,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'attempts': 0,
    });
    await _write(prefs, items);
    debugPrint('DeferredQueue: enqueued $opId ($settlementAmount)');
  }

  /// Navbatdagi elementlar soni.
  static Future<int> pendingCount() async {
    final prefs = await SharedPreferences.getInstance();
    return _read(prefs).length;
  }

  /// Navbatni server'ga yuboradi. Muvaffaqiyatli → o'chiriladi; tarmoq
  /// xatosi → keyingi urinishga qoladi; doimiy klient xatosi → tashlanadi.
  /// Idempotent (opId) — qayta yuborish xavfsiz.
  static Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      var items = _read(prefs);
      if (items.isEmpty) return;

      final remaining = <Map<String, dynamic>>[];
      for (final item in items) {
        final opId = (item['opId'] ?? '').toString();
        final amount = (item['settlementAmount'] as num?)?.toInt() ?? 0;
        try {
          await SettlementService.submitDeferredSettlement(
            passengerPhone: (item['passengerPhone'] ?? '').toString(),
            tripId: (item['tripId'] ?? '').toString(),
            opId: opId,
            settlementAmount: amount,
          );
          debugPrint('DeferredQueue: submitted $opId');
          // Muvaffaqiyat → navbatdan tushadi (qaytarib qo'shilmaydi).
        } on FirebaseFunctionsException catch (e) {
          if (_isPermanent(e.code)) {
            debugPrint('DeferredQueue: drop $opId (permanent: ${e.code})');
            // tashlanadi
          } else {
            final attempts = ((item['attempts'] as num?)?.toInt() ?? 0) + 1;
            if (attempts >= _maxAttempts) {
              debugPrint('DeferredQueue: drop $opId (max attempts)');
            } else {
              item['attempts'] = attempts;
              remaining.add(item);
              debugPrint('DeferredQueue: retry-later $opId (${e.code}, #$attempts)');
            }
          }
        } catch (e) {
          // Tarmoq/noma'lum xato → keyingi urinishga qoldiramiz.
          final attempts = ((item['attempts'] as num?)?.toInt() ?? 0) + 1;
          if (attempts >= _maxAttempts) {
            debugPrint('DeferredQueue: drop $opId (max attempts)');
          } else {
            item['attempts'] = attempts;
            remaining.add(item);
            debugPrint('DeferredQueue: retry-later $opId ($e, #$attempts)');
          }
        }
      }
      await _write(prefs, remaining);
    } finally {
      _flushing = false;
    }
  }

  /// Doimiy (qayta urinish foydasiz) klient xatolari.
  static bool _isPermanent(String code) {
    return code == 'invalid-argument' ||
        code == 'permission-denied' ||
        code == 'unauthenticated';
  }

  static List<Map<String, dynamic>> _read(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return <Map<String, dynamic>>[];
  }

  static Future<void> _write(
      SharedPreferences prefs, List<Map<String, dynamic>> items) async {
    if (items.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, jsonEncode(items));
    }
  }
}
