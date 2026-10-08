import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Админ сайдбари: учта такси бўлими модул ёпиқ бўлса ҳам кўринади (эга,
/// 2026-10-08). `admin_shell.dart` `dart:html`ни импорт қилади — VM тестида
/// юкланмайди, шунинг учун манба матни текширилади.
void main() {
  final src = File('lib/features/admin_web/screens/admin_shell.dart')
      .readAsStringSync();

  final start = src.indexOf('static const _sections = [');
  final end = src.indexOf('\n  ];', start);
  final sectionsSrc = src.substring(start, end);

  List<String> sectionLabels() =>
      RegExp(r"^\s+label: '([^']+)',", multiLine: true)
          .allMatches(sectionsSrc)
          .map((m) => m.group(1)!)
          .toList();

  /// Бир бўлимнинг `_AdminSection(...)` блоки.
  String sectionBlock(String label) {
    final i = sectionsSrc.indexOf("label: '$label',");
    final from = sectionsSrc.lastIndexOf('_AdminSection(', i);
    final to = sectionsSrc.indexOf('),', i);
    return sectionsSrc.substring(from, to);
  }

  const taxi = ['Маҳаллий такси', 'Шаҳарлараро такси', 'Маршрут такси'];

  test('учта такси бўлими сайдбарда, «Такси ва транспорт» гуруҳида', () {
    final labels = sectionLabels();
    for (final l in taxi) {
      expect(labels, contains(l));
      expect(sectionBlock(l), contains("group: 'Такси ва транспорт'"),
          reason: l);
    }
  });

  test('такси бўлимлари оддий админ ролига очиқ (access торайтирилмаган)', () {
    for (final l in taxi) {
      expect(sectionBlock(l), isNot(contains('access:')), reason: l);
    }
  });

  test('сайдбар модул ҳолатига боғланмайди (фақат роль)', () {
    expect(src, isNot(contains('ServiceConfigHolder')));
    expect(src, isNot(contains('HomeModuleGate')));
  });

  test('ҳар бир бўлим номига саҳифа бор (ном — `_buildSection` калити)', () {
    final labels = sectionLabels();
    expect(labels.length, greaterThan(30));
    for (final l in labels) {
      expect(src, contains("section.label == '$l'"), reason: l);
    }
  });
}
