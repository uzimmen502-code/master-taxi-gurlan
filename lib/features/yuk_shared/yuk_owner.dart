import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/formatters.dart';

/// Юк биржаси эълон эгаси — SharedPreferences'даги телефон/исм.
///
/// [id] — каноник телефон (`canonicalPhoneId`), камида 9 рақам бўлмаса бўш.
/// [name] — хом исм (бўш бўлиши мумкин; UI `yuk_you` fallback қўяди).
/// [phone] — қўнғироқ учун формат (`phoneForCall`), id бўш бўлса бўш.
class YukOwner {
  const YukOwner({required this.id, required this.name, required this.phone});

  static const empty = YukOwner(id: '', name: '', phone: '');

  final String id;
  final String name;
  final String phone;

  bool get isEmpty => id.isEmpty;

  static Future<YukOwner> load() async {
    final prefs = await SharedPreferences.getInstance();
    final ownerId = canonicalPhoneId(prefs.getString('user_phone') ?? '');
    final name = (prefs.getString('user_name') ?? '').trim();
    final me = phoneDigits(ownerId).length >= 9 ? ownerId : '';
    return YukOwner(
      id: me,
      name: name,
      phone: me.isEmpty ? '' : phoneForCall(me),
    );
  }
}
