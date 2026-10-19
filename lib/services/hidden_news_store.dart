import 'package:shared_preferences/shared_preferences.dart';

/// Фойдаланувчи ўз қурилмасида «ўчирган» хабарлар (`admin_news` ҳужжат id'лари).
///
/// Хабарнинг ўзи серверда қолади (админ тарихи, аудит, бошқа қурилмалар);
/// бу ерда фақат шу қурилма рўйхатидан яширилади. Сервер/rules ўзгармайди.
class HiddenNewsStore {
  HiddenNewsStore._();

  /// Хотира чегараси: энг эски id'лар тушиб кетади (лента барибир 50–80 та).
  static const maxIds = 500;

  static String _key(String uid) => 'hidden_news_ids_v1_$uid';

  static Future<Set<String>> load(String uid) async {
    if (uid.isEmpty) return <String>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_key(uid)) ?? const <String>[]).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  static Future<Set<String>> hide(String uid, Iterable<String> ids) async {
    if (uid.isEmpty) return <String>{};
    final prefs = await SharedPreferences.getInstance();
    final list = [...(prefs.getStringList(_key(uid)) ?? const <String>[])];
    for (final id in ids) {
      if (id.isNotEmpty && !list.contains(id)) list.add(id);
    }
    final kept =
        list.length > maxIds ? list.sublist(list.length - maxIds) : list;
    await prefs.setStringList(_key(uid), kept);
    return kept.toSet();
  }
}
