import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Эга қарори 2026-10-08: «Риэлторлик кластери» → «Кўчмас мулк кластери»
/// ҳамма жойда (бош саҳифа сарлавҳаси, хизмат доираси, экран сарлавҳаси;
/// admin панелида ҳам). Учала тил бирга ўзгаради.
void main() {
  Map<String, dynamic> load(String lang) => jsonDecode(
        File('assets/lang/$lang.json').readAsStringSync(),
      ) as Map<String, dynamic>;

  const expected = {
    'uz_Cyrl': (name: 'Кўчмас мулк кластери', old: 'Риэлторлик кластери'),
    'uz_Latn': (name: "Ko'chmas mulk klasteri", old: 'Rieltorlik klasteri'),
    'ru': (name: 'Кластер недвижимости', old: 'Риелторский кластер'),
  };

  for (final MapEntry(key: lang, value: e) in expected.entries) {
    group(lang, () {
      final m = load(lang);

      test('хизмат доираси ва экран сарлавҳаси — янги ном', () {
        expect(m['home_module_realty'], e.name);
        expect(m['realty_title'], e.name);
      });

      test('бош саҳифа бўлими сарлавҳаси — янги ном (икки нуқта билан)', () {
        expect(m['home_section_realty'], '${e.name}:');
      });

      test('эски «риэлторлик кластери» номи қолмаган', () {
        final raw = File('assets/lang/$lang.json').readAsStringSync();
        expect(raw.contains(e.old), isFalse);
      });
    });
  }

  test('admin панели — бўлим, матрица ва созламалар янги номда', () {
    final shell = File('lib/features/admin_web/screens/admin_shell.dart')
        .readAsStringSync();
    // Ном калит ҳам: бўлим, экран ва badge учала жойда бир хил бўлиши шарт.
    expect("label: 'Кўчмас мулк кластери'".allMatches(shell), hasLength(1));
    expect("section.label == 'Кўчмас мулк кластери'".allMatches(shell),
        hasLength(1));
    expect("case 'Кўчмас мулк кластери':".allMatches(shell), hasLength(1));
    expect(shell.contains("'Кўчмас мулк'"), isFalse);

    final svc =
        File('lib/features/admin_web/screens/service_config_admin_screen.dart')
            .readAsStringSync();
    expect(svc.contains("'realty': 'Кўчмас мулк кластери'"), isTrue);
  });
}
