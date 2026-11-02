import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// «Хабарлар» қаторларининг ЎҚИЛГАНЛИГИ — ҳар бир қатор алоҳида (эга, 2026-11-02:
/// «қатор очилгунча ўқилмаган бўлиб туради», бошқа иловалар каби).
///
/// Қурилмада сақланади (серверга ЯНГИ ёзув йўқ). Сервердаги `lastNewsReadAt` /
/// `lastMessagesReadAt` / `lastOrderNewsReadAt` эса аввалгидек бош менюдаги
/// белги (badge) учун ишлайди: экран очилганда тозаланади.
///
/// Қатор жирний: `oxirgiVaqt > max(baseline[бўлим], opened[калит])`.
/// `baseline` — бу экран ШУ қурилмада биринчи очилгандаги сервер «ўқилди»
/// вақти (кейин фақат «Ҳаммасини ўқилган қилиш» билан олдинга силжийди),
/// шунинг учун экранни ёпиб-очиш қаторни «ўқилган» қилиб қўймайди.
///
/// Чегара: бошқа қурилмада очилган қатор бу ерда жирний қолиши мумкин
/// (онгли танлов — серверга ёзув қўшмаслик учун).
class InboxReadStore {
  InboxReadStore._(this._opened, this._baseline);

  static const openedKey = 'inbox_opened_v1';
  static const baselineKey = 'inbox_baseline_v1';

  /// Эски калитлар тозаланади: 90 кундан эски очилганлик керак эмас
  /// (рўйхатда бундай эски хабар деярли йўқ, хотира ўсмайди).
  static const Duration keep = Duration(days: 90);

  final Map<String, int> _opened;
  final Map<String, int> _baseline;

  /// Хотирада, сақланмайди (тест ёки SharedPreferences ишламаса).
  factory InboxReadStore.memory() => InboxReadStore._({}, {});

  static Future<InboxReadStore> load({DateTime? now}) async {
    try {
      final p = await SharedPreferences.getInstance();
      final opened = _decode(p.getString(openedKey));
      final cut = (now ?? DateTime.now()).subtract(keep).millisecondsSinceEpoch;
      opened.removeWhere((_, v) => v < cut);
      return InboxReadStore._(opened, _decode(p.getString(baselineKey)));
    } catch (e) {
      debugPrint('[InboxReadStore] load: $e');
      return InboxReadStore.memory();
    }
  }

  static Map<String, int> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return {};
      return {
        for (final e in m.entries)
          if (e.value is num) '${e.key}': (e.value as num).toInt(),
      };
    } catch (_) {
      return {};
    }
  }

  /// Бўлим учун baseline бор-йўқлиги (биринчи очилишни аниқлаш).
  bool hasBaseline(String feed) => _baseline.containsKey(feed);

  DateTime? baseline(String feed) {
    final v = _baseline[feed];
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
  }

  DateTime? openedAt(String key) {
    final v = _opened[key];
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
  }

  /// [latest] — қатордаги энг сўнгги хабар вақти.
  bool isUnread({required String feed, required String key, required DateTime latest}) {
    final b = _baseline[feed];
    // Baseline номаълум — ҳеч нарса «янги» эмас (аввалги `NewsReadState.unknown` каби).
    if (b == null) return false;
    final o = _opened[key];
    final seen = (o != null && o > b) ? o : b;
    return latest.millisecondsSinceEpoch > seen;
  }

  /// Биринчи очилишда: сервердаги «ўқилди» вақти (ҳеч қачон ўқимаган бўлса —
  /// [fallback], одатда «ҳозир»дан анча олдин эмас — эски хабарлар жирний бўлиб
  /// кетмасин). Мавжуд baseline'га тегмайди.
  Future<void> ensureBaseline(String feed, DateTime? serverReadAt, {required DateTime fallback}) async {
    if (_baseline.containsKey(feed)) return;
    _baseline[feed] = (serverReadAt ?? fallback).millisecondsSinceEpoch;
    await _save();
  }

  Future<void> markOpened(String key, {DateTime? at}) async {
    _opened[key] = (at ?? DateTime.now()).millisecondsSinceEpoch;
    await _save();
  }

  /// «Ҳаммасини ўқилган қилиш».
  Future<void> markAllRead(Iterable<String> feeds, {DateTime? at}) async {
    final ms = (at ?? DateTime.now()).millisecondsSinceEpoch;
    for (final f in feeds) {
      _baseline[f] = ms;
    }
    _opened.clear();
    await _save();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(openedKey, jsonEncode(_opened));
      await p.setString(baselineKey, jsonEncode(_baseline));
    } catch (e) {
      debugPrint('[InboxReadStore] save: $e');
    }
  }
}
