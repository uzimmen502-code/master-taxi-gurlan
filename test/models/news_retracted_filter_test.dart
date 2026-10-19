// ignore_for_file: subtype_of_sealed_class
import 'package:ava_gurlan/models/news_item.dart';
import 'package:ava_gurlan/repositories/news_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Админ хабарни ҚАЙТАРИБ олганда (`adminRetractNews`, 2026-10-20) фойдаланувчи лентаси ва ўқилмаганлар ҳисоби
/// уни кўрсатмаслиги. Сервер `retractedAt` қўяди ва `audience: 'retracted'` ёзади (эски APK шу орқали яширади);
/// янги APK `retractedAt` бўйича ҳам филтрлайди.
class _Snap implements DocumentSnapshot<Map<String, dynamic>> {
  _Snap(this.id, this._data);
  @override
  final String id;
  final Map<String, dynamic> _data;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  NewsItem news(String id,
          {String audience = 'all',
          String targetUserId = '',
          String category = 'info',
          String source = '',
          DateTime? retractedAt}) =>
      NewsItem(
        id: id,
        title: 'T$id',
        body: 'B',
        createdAt: DateTime(2026, 10, 20),
        audience: audience,
        targetUserId: targetUserId,
        category: category,
        source: source,
        retractedAt: retractedAt,
      );

  const passenger = ['all', 'user'];
  const uid = '998901112233';
  final at = DateTime(2026, 10, 20, 10);

  group('NewsItem.retractedAt', () {
    test('fromDoc: Timestamp → DateTime; майдони йўқ эски ҳужжат → null', () {
      final withField = NewsItem.fromDoc(_Snap('a', {
        'title': 'T',
        'body': 'B',
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
        'audience': 'retracted',
        'retractedAt': Timestamp.fromDate(at),
      }));
      expect(withField.retractedAt, at);
      expect(withField.isRetracted, isTrue);

      final old = NewsItem.fromDoc(_Snap('b', {
        'title': 'T',
        'body': 'B',
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
      }));
      expect(old.retractedAt, isNull);
      expect(old.isRetracted, isFalse);
    });

    test('«retracted» аудитория (эски APK логикаси) ҳеч кимга кўринмайди', () {
      expect(
          news('x', audience: 'retracted')
              .isVisibleTo(userId: uid, audiences: passenger),
          isFalse);
    });
  });

  group('NewsRepository — қайтариб олинган хабар лентада йўқ', () {
    test('_filterForUser: ommaviy retracted чиқиб кетади, oddiy қолади', () {
      final out = NewsRepository.filterForUserForTesting(
        [
          news('live'),
          news('gone', retractedAt: at),
          // retractedAt бор, аудитория ўзгармаган (янги клиентнинг ўз филтри синалади)
        ],
        audiences: passenger,
        userId: uid,
        feed: NewsFeedKind.broadcast,
      );
      expect(out.map((n) => n.id), ['live']);
    });

    test('шахсий хабар ҳам бир хил филтрдан ўтади (retractedAt бор бўлса)', () {
      final personal = news('p',
          audience: 'user', targetUserId: uid, source: 'identity_request');
      final personalRetracted = news('pr',
          audience: 'user',
          targetUserId: uid,
          source: 'identity_request',
          retractedAt: at);
      final out = NewsRepository.filterForUserForTesting(
        [personal, personalRetracted],
        audiences: passenger,
        userId: uid,
        feed: NewsFeedKind.dialog,
      );
      expect(out.map((n) => n.id), ['p']);
    });

    test('буюртма хабари: retractedAt бўлмаса қолади', () {
      final order = news('o',
          audience: 'user',
          targetUserId: uid,
          category: 'order',
          source: 'order_status');
      final out = NewsRepository.filterForUserForTesting(
        [order],
        audiences: passenger,
        userId: uid,
        feed: NewsFeedKind.order,
      );
      expect(out.map((n) => n.id), ['o']);
    });

    test('ўқилмаганлар ҳисоби: retracted саналмайди, oddiy саналади', () {
      expect(
          NewsRepository.countsAsUnreadForTesting(news('live'),
              audiences: passenger,
              userId: uid,
              feed: NewsFeedKind.broadcast),
          isTrue);
      expect(
          NewsRepository.countsAsUnreadForTesting(
              news('gone', retractedAt: at),
              audiences: passenger,
              userId: uid,
              feed: NewsFeedKind.broadcast),
          isFalse);
      // шахсий, retractedAt билан — ҳам саналмайди (бир хил филтр)
      expect(
          NewsRepository.countsAsUnreadForTesting(
              news('pr',
                  audience: 'user',
                  targetUserId: uid,
                  source: 'identity_request',
                  retractedAt: at),
              audiences: passenger,
              userId: uid,
              feed: NewsFeedKind.dialog),
          isFalse);
    });
  });
}
