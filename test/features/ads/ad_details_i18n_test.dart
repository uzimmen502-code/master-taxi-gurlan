import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Уч тил қоидаси (эга, memory: three-language-text-rule): UI матни қотирилмайди,
/// uz_Cyrl / uz_Latn / ru учаласида калит бўлади. Аҳоли тафсилотида 16 та матн
/// қотирилган эди — русча/лотин тилда кирилл ўзбекча чиқар эди (2026-10-17,
/// қурилмада кўрилган).
void main() {
  const keys = [
    'ad_details_phone_invalid',
    'ad_details_call_failed',
    'ad_details_views',
    'ad_details_similar_error',
    'ad_details_similar_empty',
    'ad_report_title',
    'ad_report_sent',
    'ad_report_limit',
    'ad_report_reason_fraud',
    'ad_report_reason_phone',
    'ad_report_reason_spam',
    'ad_report_reason_abuse',
  ];

  Map<String, dynamic> load(String lang) => jsonDecode(
        File('assets/lang/$lang.json').readAsStringSync(),
      ) as Map<String, dynamic>;

  final langs = {
    'uz_Cyrl': load('uz_Cyrl'),
    'uz_Latn': load('uz_Latn'),
    'ru': load('ru'),
  };

  for (final k in keys) {
    test('калит $k — учала тилда бор ва бўш эмас', () {
      for (final e in langs.entries) {
        final v = e.value[k];
        expect(v, isA<String>(), reason: '${e.key}: $k йўқ');
        expect((v as String).trim(), isNotEmpty, reason: '${e.key}: $k бўш');
      }
    });
  }

  test('ad_details_views — {count} ўринбосари учала тилда', () {
    for (final e in langs.entries) {
      expect(e.value['ad_details_views'], contains('{count}'), reason: e.key);
    }
  });

  test('лотин ва рус таржимаси кирилл ўзбекчанинг нусхаси эмас', () {
    for (final k in keys) {
      final cyrl = langs['uz_Cyrl']![k] as String;
      expect(langs['uz_Latn']![k], isNot(cyrl), reason: 'uz_Latn: $k');
      expect(langs['ru']![k], isNot(cyrl), reason: 'ru: $k');
    }
  });

  test('ad_details_screen.dart: қотирилган кирилл UI матни йўқ '
      '(шикоят ҚИЙМАТЛАРИ — серверга кетадиган — бундан мустасно)', () {
    final src = File('lib/features/ads/screens/ad_details_screen.dart')
        .readAsStringSync();
    // Серверга юбориладиган шикоят сабаблари (мавжуд шикоятлар билан мос).
    const serverValues = [
      'Алдамчи эълон',
      'Телефон нотўғри',
      'Спам / Такрорий',
      'Ҳақоратли матн',
    ];
    final literal = RegExp("['\"][^'\"\\n]*[А-Яа-яЎўҚқҒғҲҳ][^'\"\\n]*['\"]");
    final bad = <String>[];
    for (final line in src.split('\n')) {
      final t = line.trim();
      if (t.startsWith('//') || t.startsWith('///')) continue;
      for (final m in literal.allMatches(t)) {
        final text = m.group(0)!;
        if (serverValues.any(text.contains)) continue;
        bad.add(text);
      }
    }
    expect(bad, isEmpty, reason: 'қотирилган матн: $bad');
  });
}
