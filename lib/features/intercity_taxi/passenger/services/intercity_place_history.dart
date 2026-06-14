import 'package:shared_preferences/shared_preferences.dart';

/// Шаҳарлараро «Қаердан» / «Қаерга» oxirgi tanlovlari (kanonik kirill).
class IntercityPlaceHistory {
  IntercityPlaceHistory._();

  static const _fromKey = 'intercity_recent_from';
  static const _toKey = 'intercity_recent_to';
  static const maxItems = 8;

  static Future<List<String>> loadFrom() async {
    final prefs = await SharedPreferences.getInstance();
    return List<String>.from(prefs.getStringList(_fromKey) ?? const []);
  }

  static Future<List<String>> loadTo() async {
    final prefs = await SharedPreferences.getInstance();
    return List<String>.from(prefs.getStringList(_toKey) ?? const []);
  }

  static Future<void> addFrom(String canonical) =>
      _add(_fromKey, canonical);

  static Future<void> addTo(String canonical) => _add(_toKey, canonical);

  static Future<void> _add(String key, String raw) async {
    final canonical = raw.trim();
    if (canonical.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final list = List<String>.from(prefs.getStringList(key) ?? const []);
    list.remove(canonical);
    list.insert(0, canonical);
    if (list.length > maxItems) {
      list.removeRange(maxItems, list.length);
    }
    await prefs.setStringList(key, list);
  }
}
