import 'dart:convert';

import 'package:ava_gurlan/features/tv_market/services/tv_feed_cdn.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

/// CDN жавобини сохталаштиради.
void stub(int status, Object? body) {
  TvFeedCdn.getOverride = (url) async => http.Response(
        body is String ? body : jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
}

Map<String, dynamic> page({
  int v = 1,
  int pages = 2,
  int? builtAtMs,
  List<Object?>? clips,
}) =>
    {
      'v': v == 1 ? 'v1' : 'v$v',
      'districtId': 'gurlan',
      'tab': 'all',
      'page': 1,
      'pages': pages,
      'total': 25,
      'builtAtMs': builtAtMs ?? DateTime.now().millisecondsSinceEpoch,
      'clips': clips ??
          [
            {
              'id': 'c1',
              'title': 'Birinchi',
              'videoUrl': 'https://x/v.mp4',
              'hlsUrl': 'https://video.ava-uz.com/processed/c1/r1/master.m3u8',
              'category': 'product',
              'viewCount': 7,
              'createdAtMs': 1700000000000,
            },
          ],
    };

void main() {
  tearDown(() => TvFeedCdn.getOverride = null);

  group('tabFor — клиентдаги _categoriesForTab билан мослик', () {
    test('null (AVAGram) -> all', () => expect(TvFeedCdn.tabFor(null), 'all'));
    test('бўш рўйхат -> all', () => expect(TvFeedCdn.tabFor([]), 'all'));
    test("['news'] -> news",
        () => expect(TvFeedCdn.tabFor(['news']), 'news'));
    test("['product','service','ad'] -> market", () {
      expect(TvFeedCdn.tabFor(['product', 'service', 'ad']), 'market');
    });
    test('нотаниш комбинация -> null (CDN’да ҳовуз йўқ)', () {
      expect(TvFeedCdn.tabFor(['product']), isNull);
      expect(TvFeedCdn.tabFor(['news', 'ad']), isNull);
    });
  });

  group('URL', () {
    test('йўл сервердаги feedPageKey билан бир хил', () {
      expect(
        TvFeedCdn.pageUrl('gurlan', 'news', 3).toString(),
        'https://video.ava-uz.com/feed/v1/gurlan/news/p3.json',
      );
    });
  });

  group('fetchPage — муваффақият', () {
    test('клиплар ўқилади, createdAtMs санага айланади', () async {
      stub(200, page());
      final r = await TvFeedCdn.fetchPage(
          districtId: 'gurlan', categories: null);
      expect(r, isNotNull);
      expect(r!.clips.length, 1);
      expect(r.clips.first.id, 'c1');
      expect(r.clips.first.title, 'Birinchi');
      expect(r.clips.first.viewCount, 7);
      expect(r.clips.first.createdAt,
          DateTime.fromMillisecondsSinceEpoch(1700000000000));
      expect(r.hasMore, isTrue);
    });

    test('охирги саҳифада hasMore false', () async {
      stub(200, page(pages: 1));
      final r = await TvFeedCdn.fetchPage(
          districtId: 'gurlan', categories: null);
      expect(r!.hasMore, isFalse);
    });

    test('бузуқ ёзув ташланади, қолгани ўқилади', () async {
      stub(
        200,
        page(clips: <Object?>[
          {'id': '', 'title': 'id yo\'q'},
          {'title': 'id umuman yo\'q'},
          'satr',
          {'id': 'ok', 'title': 'Yaxshi'},
        ]),
      );
      // `satr` Map эмас — parser уни ўтказиб юборади.
      final r = await TvFeedCdn.fetchPage(
          districtId: 'gurlan', categories: null);
      expect(r!.clips.map((c) => c.id), ['ok']);
    });
  });

  group('fetchPage — ҚАЙТИШ ЙЎЛИ (null қайтариши шарт)', () {
    test('404 — JSON ҳали ёзилмаган', () async {
      stub(404, '');
      expect(
          await TvFeedCdn.fetchPage(districtId: 'g', categories: null), isNull);
    });

    test('бузуқ JSON', () async {
      stub(200, 'bu json emas');
      expect(
          await TvFeedCdn.fetchPage(districtId: 'g', categories: null), isNull);
    });

    test('бошқа схема версияси', () async {
      stub(200, page(v: 2));
      expect(
          await TvFeedCdn.fetchPage(districtId: 'g', categories: null), isNull);
    });

    test('ЭСКИРГАН JSON — builder тўхтаб қолган', () async {
      final old = DateTime.now()
          .subtract(TvFeedCdn.maxAge + const Duration(minutes: 1));
      stub(200, page(builtAtMs: old.millisecondsSinceEpoch));
      expect(
          await TvFeedCdn.fetchPage(districtId: 'g', categories: null), isNull);
    });

    test('builtAtMs йўқ', () async {
      final p = page()..remove('builtAtMs');
      stub(200, p);
      expect(
          await TvFeedCdn.fetchPage(districtId: 'g', categories: null), isNull);
    });

    test('тармоқ хатоси', () async {
      TvFeedCdn.getOverride = (_) async => throw Exception('tarmoq yo\'q');
      expect(
          await TvFeedCdn.fetchPage(districtId: 'g', categories: null), isNull);
    });

    test('туман бўш', () async {
      stub(200, page());
      expect(
          await TvFeedCdn.fetchPage(districtId: '', categories: null), isNull);
    });

    test('нотаниш таб — сўров умуман юборилмайди', () async {
      var called = false;
      TvFeedCdn.getOverride = (_) async {
        called = true;
        return http.Response('', 200);
      };
      final r = await TvFeedCdn.fetchPage(
          districtId: 'g', categories: ['product']);
      expect(r, isNull);
      expect(called, isFalse);
    });
  });
}
