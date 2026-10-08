import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Admin рўйхатлари «энг янгиси биринчи» тартибида СЕРВЕРДА кесилсин
/// (эга, 2026-10-08 — «500 талик чегара»), давоми — «Яна юклаш» билан.
///
/// Нуқсон: рўйхатлар 500 тага кесиларди, лекин тартиб йўқ эди (бозор,
/// улгуржи) ёки бошқа турлар билан аралаш эди (эълонлар) — ҳужжатлар 500
/// дан ошса, янги/кутаётган эълон нишонда саналиб, рўйхатда чиқмасди.
/// Production'да (2026-10-08) ҳужжатлар кам (ads 124, wholesale 9) — хавф
/// келажакда эди. Сўровлар production'да REST орқали текширилган: индекс
/// бўлмаганда «requires an index», индекс билан — ОК.
///
/// Firestore'ни сохталаштирадиган кутубхона лойиҳада йўқ — тест сўровнинг
/// ўзини манбадан қулфлайди. Саҳифалаш мантиғи —
/// `admin_paged_list_test.dart`, сервер саҳифалари — emulator тести
/// `functions/test/admin_market_list.test.js`.
void main() {
  String body(String path, String start, String end) {
    final src = File(path).readAsStringSync();
    final from = src.indexOf(start);
    expect(from, isNot(-1), reason: '$start топилмади ($path)');
    return src.substring(from, src.indexOf(end, from));
  }

  test('эълонлар (admin): тур филтри серверда, энг янгиси биринчи', () {
    final head = body('lib/repositories/jobs_repository.dart',
        'adminListQuery()', ';');
    expect(head, contains("where('type', whereIn: JobAd.jobsBoardTypes)"));
    expect(head, contains("orderBy('createdAt', descending: true)"));
  });

  test('улгуржи (admin): энг янгиси биринчи', () {
    final head = body(
        'lib/features/wholesale/repositories/wholesale_products_repository.dart',
        'adminListQuery()',
        ';');
    expect(head, contains("orderBy('createdAt', descending: true)"));
  });

  for (final (name, path, field) in const [
    (
      'эълонлар',
      'lib/features/admin_web/screens/jobs_moderation_screen.dart',
      '_ads'
    ),
    (
      'улгуржи',
      'lib/features/admin_web/screens/wholesale_moderation_screen.dart',
      '_products'
    ),
  ]) {
    test('$name экрани: саҳифалар initState да бир марта очилади, тугма бор',
        () {
      final init = body(path, 'void initState()', 'void dispose()');
      expect(init, contains('$field = AdminFirestorePagedList'));
      expect(init, contains('adminListQuery()'));
      expect(init, contains('watchFirestoreWindow(query, window)'));
      final dispose = body(path, 'void dispose()', '}');
      expect(dispose, contains('$field.dispose()'));
      expect(File(path).readAsStringSync(), contains('AdminLoadMoreBar('));
    });
  }

  test('аҳоли бозори (CF): энг янгиси биринчи, ID билан барқарор курсор', () {
    final page = body('functions/admin_market_list.js',
        'async function listMarketAdsPage', '.get();');
    expect(page, contains(".where('type', '==', 'cheap_product')"));
    expect(page, contains(".orderBy('createdAt', 'desc')"));
    expect(page,
        contains(".orderBy(admin.firestore.FieldPath.documentId(), 'desc')"));
    expect(page, contains('startAfter(after.createdAt, after.id)'));
    expect(page.indexOf('.orderBy('), lessThan(page.indexOf('.limit(')));
  });

  test('аҳоли бозори (CF): саҳифа ва nextCursor қайтаради', () {
    final cf = body('functions/index.js', 'exports.adminListMarketAds',
        '\n});');
    expect(cf, contains('parseMarketAdsCursor(data.after'));
    expect(cf, contains('listMarketAdsPage(db'));
    expect(cf, contains('return { ads, nextCursor };'));
    expect(cf, isNot(contains('data.pageSize')),
        reason: 'саҳифа ҳажмини клиент белгиламайди');
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
