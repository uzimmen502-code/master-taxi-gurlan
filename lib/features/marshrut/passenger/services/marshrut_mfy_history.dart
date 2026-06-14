import 'package:shared_preferences/shared_preferences.dart';

/// Marshrut «Қаerдан» / «Қaerga» MFY oxirgi tanlovlari (SharedPreferences).
class MarshrutMfyHistory {
  MarshrutMfyHistory._();

  static const _fromKey = 'marshrut_mfy_recent_from';
  static const _toKey = 'marshrut_mfy_recent_to';
  static const maxItems = 8;

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
