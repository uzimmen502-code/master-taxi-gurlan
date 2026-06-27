import 'package:url_launcher/url_launcher.dart';

import 'formatters.dart';

/// Телефон рақамига қўнғироқ қилади (`tel:` URI).
///
/// Аввал ҳар бир экранда `Uri.parse('tel:...')` + `launchUrl` алоҳида
/// такрорланарди. Энди ягона жойда. Рақам нотўғри бўлса (9 рақамдан кам)
/// ҳеч нарса қилмайди ва `false` қайтаради; хатони ютади.
Future<bool> callPhone(String rawPhone) async {
  if (phoneDigits(rawPhone).length < 9) return false;
  final uri = Uri.parse('tel:${phoneForCall(rawPhone)}');
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
