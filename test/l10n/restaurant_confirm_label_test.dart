import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Эга, 2026-10-31: «Уй ошпази бўлиш» / «Кафе-ресторан очиш» — «Ариза юбориш» занжири керак эмас,
/// ўрнига «Тасдиқлайман» тугмаси; объект дарҳол жонли (сервер `settings/app.restaurantAutoApprove`).
void main() {
  const expected = {
    'uz_Cyrl': 'Тасдиқлайман',
    'uz_Latn': 'Tasdiqlayman',
    'ru': 'Подтверждаю',
  };
  for (final e in expected.entries) {
    test('${e.key}: рўйхатдан ўтиш тугмаси — «${e.value}», «ариза» сўзи йўқ', () {
      final map = jsonDecode(File('assets/lang/${e.key}.json').readAsStringSync()) as Map<String, dynamic>;
      final label = map['restaurants_m_submit'] as String;
      expect(label, e.value);
      expect(label.toLowerCase(), isNot(anyOf(contains('ариза'), contains('ariza'), contains('заявк'))));
    });
  }
}
