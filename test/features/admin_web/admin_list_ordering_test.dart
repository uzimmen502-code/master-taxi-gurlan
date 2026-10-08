import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Admin рўйхатлари «энг янгиси биринчи» тартибида СЕРВЕРДА кесилсин
/// (эга, 2026-10-08 — «500 талик чегара»).
///
/// Нуқсон: рўйхатлар 500 тага кесиларди, лекин тартиб йўқ эди (бозор,
/// улгуржи) ёки бошқа турлар билан аралаш эди (эълонлар) — ҳужжатлар 500
/// дан ошса, янги/кутаётган эълон нишонда саналиб, рўйхатда чиқмасди.
/// Production'да (2026-10-08) ҳужжатлар кам (ads 124, wholesale 9) — хавф
/// келажакда эди. Сўровлар production'да REST орқали текширилган: индекс
/// бўлмаганда «requires an index», индекс билан — ОК.
///
/// Firestore'ни сохталаштирадиган кутубхона лойиҳада йўқ — тест сўровнинг
/// ўзини манбадан қулфлайди.
void main() {
  test('эълонлар (admin): тур филтри серверда, энг янгиси биринчи', () {
    final src = File('lib/repositories/jobs_repository.dart').readAsStringSync();
    final body = src.substring(src.indexOf('watchAllForAdmin({int limit'));
    final head = body.substring(0, body.indexOf('.snapshots()'));
    expect(head, contains("where('type', whereIn: JobAd.jobsBoardTypes)"));
    expect(head, contains("orderBy('createdAt', descending: true)"));
    expect(head.indexOf('where('), lessThan(head.indexOf('.limit(')));
  });

  test('улгуржи (admin): энг янгиси биринчи, кейин limit', () {
    final src = File(
            'lib/features/wholesale/repositories/wholesale_products_repository.dart')
        .readAsStringSync();
    final body = src.substring(src.indexOf('watchAllForAdmin({'));
    final head = body.substring(0, body.indexOf('.snapshots()'));
    expect(head, contains("orderBy('createdAt', descending: true)"));
    expect(head.indexOf('orderBy('), lessThan(head.indexOf('.limit(')));
  });

  test('аҳоли бозори (CF adminListMarketAds): энг янгиси биринчи', () {
    final src = File('functions/index.js').readAsStringSync();
    final start = src.indexOf('exports.adminListMarketAds');
    final body = src.substring(start, src.indexOf('.get();', start));
    expect(body, contains(".where('type', '==', 'cheap_product')"));
    expect(body, contains(".orderBy('createdAt', 'desc')"));
    expect(body.indexOf('.orderBy('), lessThan(body.indexOf('.limit(')));
  });

  test('индекс ads (type ASC, createdAt DESC) репо файлида бор', () {
    final src = File('firestore.indexes.json').readAsStringSync()
        .replaceAll(RegExp(r'\s+'), '');
    expect(
      src,
      contains('"collectionGroup":"ads","queryScope":"COLLECTION","fields":'
          '[{"fieldPath":"type","order":"ASCENDING"},'
          '{"fieldPath":"createdAt","order":"DESCENDING"}]'),
    );
  });
}
