import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Эга қарори 2026-10-08: «Риэлторлик кластери» → «Кўчмас мулк кластери»;
/// 2026-11-15 («Бозорлар» 7-босқич): → «Уй-жой бозори» / «Uy-joy bozori» / «Недвижимость»
/// ҳамма жойда (бош саҳифа сарлавҳаси, хизмат доираси, экран сарлавҳаси; admin панелида ҳам).
/// Учала тил бирга ўзгаради.
void main() {
  Map<String, dynamic> load(String lang) => jsonDecode(
        File('assets/lang/$lang.json').readAsStringSync(),
      ) as Map<String, dynamic>;

  const expected = {
    'uz_Cyrl': (name: 'Уй-жой бозори', old: ['Риэлторлик кластери', 'Кўчмас мулк кластери']),
    'uz_Latn': (name: 'Uy-joy bozori', old: ['Rieltorlik klasteri', "Ko'chmas mulk klasteri"]),
    'ru': (name: 'Недвижимость', old: ['Риелторский кластер', 'Кластер недвижимости']),
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

      test('эски «кластер» номлари қолмаган', () {
        final raw = File('assets/lang/$lang.json').readAsStringSync();
        for (final o in e.old) {
          expect(raw.contains(o), isFalse, reason: o);
        }
      });
    });
  }

  test('admin панели — бўлим, маршрут ва нишон янги номда (маршрут ЛЕЙБЛ бўйича)', () {
    final shell = File('lib/features/admin_web/screens/admin_shell.dart')
        .readAsStringSync();
    // Ном калит ҳам: бўлим, экран ва badge учала жойда бир хил бўлиши шарт.
    expect("label: 'Уй-жой бозори'".allMatches(shell), hasLength(1));
    expect("section.label == 'Уй-жой бозори'".allMatches(shell), hasLength(1));
    expect("case 'Уй-жой бозори':".allMatches(shell), hasLength(1));
    expect(shell.contains("'Кўчмас мулк кластери'"), isFalse);
    expect(shell.contains("'Кўчмас мулк'"), isFalse);

    final svc =
        File('lib/features/admin_web/screens/service_config_admin_screen.dart')
            .readAsStringSync();
    expect(svc.contains("'realty': 'Уй-жой бозори'"), isTrue);
    final settings =
        File('lib/features/admin_web/screens/realty_settings_admin_panel.dart')
            .readAsStringSync();
    expect(settings.contains('Кўчмас мулк кластери'), isFalse);
  });
}