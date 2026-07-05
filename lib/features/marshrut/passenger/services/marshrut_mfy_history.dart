import 'package:shared_preferences/shared_preferences.dart';

import '../models/marshrut_route_pair.dart';

/// Marshrut «Қаerдан» / «Қaerga» MFY oxirgi tanlovlari (SharedPreferences).
class MarshrutMfyHistory {
  MarshrutMfyHistory._();

  static const _fromKey = 'marshrut_mfy_recent_from';
  static const _toKey = 'marshrut_mfy_recent_to';
  static const _routesKey = 'marshrut_mfy_recent_routes';
  static const maxItems = 8;
  static const maxRoutes = 6;

  static Future<List<String>> loadFrom() async {
    final prefs = await SharedPreferences.getInstance();
    return List<String>.from(prefs.getStringList(_fromKey) ?? const []);
  }

  static Future<List<String>> loadTo() async {
    final prefs = await SharedPreferences.getInstance();
    return List<String>.from(prefs.getStringList(_toKey) ?? const []);
  }

  static Future<void> addFrom(String mfy) => _add(_fromKey, mfy);

  static Future<void> addTo(String mfy) => _add(_toKey, mfy);

  static Future<List<MarshrutRoutePair>> loadRecentRoutes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_routesKey) ?? const [];
    final routes = <MarshrutRoutePair>[];
    for (final entry in raw) {
      final parts = entry.split('|');
      if (parts.length != 2) continue;
      final from = parts[0].trim();
      final to = parts[1].trim();
      if (from.isEmpty || to.isEmpty || from == to) continue;
      routes.add(MarshrutRoutePair(from: from, to: to));
    }
    return routes;
  }

  static Future<void> addRoute(String from, String to) async {
    final f = from.trim();
    final t = to.trim();
    if (f.isEmpty || t.isEmpty || f == t) return;
    final prefs = await SharedPreferences.getInstance();
    final list = List<String>.from(prefs.getStringList(_routesKey) ?? const []);
    final encoded = '$f|$t';
    list.remove(encoded);
    list.insert(0, encoded);
    if (list.length > maxRoutes) {
      list.removeRange(maxRoutes, list.length);
    }
    await prefs.setStringList(_routesKey, list);
  }

  static Future<void> _add(String key, String mfy) async {
    final trimmed = mfy.trim();
    if (trimmed.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = List<String>.from(prefs.getStringList(key) ?? const []);
    list.remove(trimmed);
    list.insert(0, trimmed);
    if (list.length > maxItems) {
      list.removeRange(maxItems, list.length);
    }
    await prefs.setStringList(key, list);
  }
}
