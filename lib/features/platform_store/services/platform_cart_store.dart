import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';

/// AVA товари саватини қурилмада сақлайди (`productId → миқдор`).
///
/// Нима учун: сават аввал фақат контроллер хотирасида эди, контроллер эса
/// товар тафсилоти маршрути билан яратилиб, у ёпилганда ўлади. «Орқага»
/// босилса сават жимгина йўқолар эди (2026-10-17).
///
/// Фақат ID ва миқдор сақланади — нарх ЭМАС: нарх ҳар сафар каталогдан
/// ва серверда ҳисобланади (CLAUDE.md 18). Сават фойдаланувчи телефони
/// бўйича ажратилади — бир қурилмада бошқа аккаунт кирса, эскисининг
/// саватини кўрмайди.
class PlatformCartStore {
  static const _prefix = 'platform_cart_v1_';

  /// Телефонсиз (кирмаган) ҳолат учун.
  static const _guest = 'guest';

  String keyFor(String phone) {
    final digits = phoneDigits(phone);
    return '$_prefix${digits.isEmpty ? _guest : digits}';
  }

  Future<String> _currentKey() async {
    final prefs = await SharedPreferences.getInstance();
    return keyFor(prefs.getString('user_phone') ?? '');
  }

  Future<Map<String, int>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(await _currentKey());
      if (raw == null || raw.isEmpty) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final out = <String, int>{};
      decoded.forEach((k, v) {
        if (k is String && v is int && v > 0) out[k] = v;
      });
      return out;
    } catch (e) {
      // Бузилган ёзув сават бўшлигини англатади — экран ишлайверади.
      debugPrint('[PlatformCartStore] load: $e');
      return const {};
    }
  }

  Future<void> save(Map<String, int> cart) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = await _currentKey();
      if (cart.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, jsonEncode(cart));
      }
    } catch (e) {
      debugPrint('[PlatformCartStore] save: $e');
    }
  }
}
