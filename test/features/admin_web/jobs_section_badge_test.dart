import 'dart:io';

import 'package:ava_gurlan/models/job_ad.dart';
import 'package:flutter_test/flutter_test.dart';

/// Admin «Эълонлар ва хизматлар» (аввал «ИШ ЭЪЛОН») — эга, 2026-10-08.
///
/// Нуқсон: нишон бўш ва `announcement` турли кутаётган эълонларни ҳам
/// санарди, экран эса фақат `work|service|ad` ни кўрсатарди — нишон
/// нолга тушмасди, эълонни эса топиб бўлмасди. Энди иккаласи ҳам
/// [JobAd.jobsBoardTypes] дан олади.
void main() {
  group('JobAd.jobsBoardTypes — ягона манба', () {
    test('иш, хизмат, эълон — доскада (positive)', () {
      for (final t in ['work', 'service', 'ad']) {
        expect(JobAd.isJobsBoardType(t), isTrue, reason: t);
        expect(JobAd.jobsBoardTypes, contains(t));
      }
    });

    test('бозор, эски ва бўш турлар — доскада эмас (negative)', () {
      for (final t in ['cheap_product', 'sell', 'announcement', '', null]) {
        expect(JobAd.isJobsBoardType(t), isFalse, reason: '$t');
      }
    });

    // Firestore `whereIn` 1..30 қийматни қабул қилади.
    test('whereIn чегараси: 1..30 қиймат (boundary)', () {
      expect(JobAd.jobsBoardTypes, isNotEmpty);
      expect(JobAd.jobsBoardTypes.length, lessThanOrEqualTo(30));
    });
  });

  test('admin: бўлим номи, экран ва нишон калити бир хил', () {
    final shell = File('lib/features/admin_web/screens/admin_shell.dart')
        .readAsStringSync();
    expect("label: 'Эълонлар ва хизматлар'".allMatches(shell), hasLength(1));
    expect("section.label == 'Эълонлар ва хизматлар'".allMatches(shell),
        hasLength(1));
    expect("case 'Эълонлар ва хизматлар':".allMatches(shell), hasLength(1));
    expect(shell.contains("'ИШ ЭЪЛОН'"), isFalse);
    // Нишон экран билан бир хил турларни санайди ва чекланган.
    expect(shell.contains('whereIn: JobAd.jobsBoardTypes'), isTrue);
    expect(shell.contains("t == 'announcement'"), isFalse);
  });

  test('admin: экран сарлавҳалари бир хил кўринишда, аралаш ёзув йўқ', () {
    final market =
        File('lib/features/admin_web/screens/market_moderation_screen.dart')
            .readAsStringSync();
    expect(market.contains("'АҲОЛИ БОЗОРИ — назорати'"), isTrue);
    expect(market.contains("— nazorati'"), isFalse);
    final jobs =
        File('lib/features/admin_web/screens/jobs_moderation_screen.dart')
            .readAsStringSync();
    expect(jobs.contains("'ЭЪЛОНЛАР ВА ХИЗМАТЛАР — назорати'"), isTrue);
  });
}
