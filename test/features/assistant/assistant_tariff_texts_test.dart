import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// AVA ёрдамчиси тарифи (эга қарори, 2026-09-22): бир марталик тўлов, нархи
/// сервердан келади (`functions/assistant_chat.js`, default `once` = 25 000).
/// Иловадаги матнларда нарх ва эски 7/15/30 кунлик пакетлар ҚАТТИҚ ёзилмайди —
/// акс ҳолда сервер нархи ўзгарганда экран ёлғон гапиради (ягона манба қоидаси).
void main() {
  for (final lang in ['uz_Cyrl', 'uz_Latn', 'ru']) {
    test('$lang: assistant_* матнларда қаттиқ нарх ва эски кунлик пакет йўқ', () {
      final json = jsonDecode(File('assets/lang/$lang.json').readAsStringSync()) as Map<String, dynamic>;
      final bad = <String>[];
      json.forEach((k, v) {
        if (!k.startsWith('assistant_') || v is! String) return;
        final hardPrice = RegExp(r'\d[\d\s]*\d\s*(сўм|сум|so.m)', caseSensitive: false).hasMatch(v) ||
            RegExp(r'\b(12|15|25|30)\s?000\b').hasMatch(v);
        final dayPack = RegExp(r'Plus\s+\d+\s*(кун|kun|дн)', caseSensitive: false).hasMatch(v);
        if (hardPrice || dayPack) bad.add(k);
      });
      expect(bad, isEmpty, reason: 'Қаттиқ нарх/кунлик пакет: $bad');
    });
  }
}
