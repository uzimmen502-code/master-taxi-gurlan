import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Bread + food offline буюртма навбати (ягона калит).
class PendingCommerceOrders {
  PendingCommerceOrders._();

  static const key = 'commerce_pending_orders';
  static const _legacyKeys = ['pending_orders', 'food_pending_orders'];

  /// Барча legacy калитларни бирлаштириб, ягона рўйхат қайтаради.
  static Future<List<Map<String, dynamic>>> load(
    SharedPreferences prefs,
  ) async {
    final out = <Map<String, dynamic>>[];
    void take(String? raw) {
      if (raw == null || raw.isEmpty) return;
      try {
        final list = jsonDecode(raw) as List;
        for (final e in list) {
          if (e is Map) {
            out.add(Map<String, dynamic>.from(e));
          }
        }
      } catch (_) {}
    }

    take(prefs.getString(key));
    for (final legacy in _legacyKeys) {
      take(prefs.getString(legacy));
    }
    return out;
  }

  static Future<void> save(
    SharedPreferences prefs,
    List<Map<String, dynamic>> orders,
  ) async {
    for (final legacy in _legacyKeys) {
      await prefs.remove(legacy);
    }
    if (orders.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, jsonEncode(orders));
    }
  }

  static Future<void> add(
    SharedPreferences prefs,
    Map<String, dynamic> order,
  ) async {
    final list = await load(prefs);
    list.add(order);
    await save(prefs, list);
  }
}
