import 'package:ava_gurlan/models/news_item.dart';
import 'package:flutter_test/flutter_test.dart';

/// Админ «Хабарлар» → аудитория танлови илова лентасида ҳақиқатан
/// ишлашини қулфлайди (админ аудит, 2026-10-08). Аввал `isVisibleTo`
/// кўрувчи рўйхатида доим бўладиган `'all'`ни текширарди — «фақат
/// ҳайдовчиларга» юборилган хабар ҳамма йўловчиларга ҳам чиқарди.
void main() {
  NewsItem news({String audience = 'all', String targetUserId = ''}) =>
      NewsItem(
        id: 'n1',
        title: 'T',
        body: 'B',
        createdAt: DateTime(2026, 10, 8),
        audience: audience,
        targetUserId: targetUserId,
      );

  const passenger = ['all', 'user'];
  const driver = ['all', 'driver'];

  group('NewsItem.isVisibleTo — аудитория', () {
    test('«all» хабар ҳаммага', () {
      expect(news().isVisibleTo(userId: '998901112233', audiences: passenger),
          isTrue);
      expect(news().isVisibleTo(userId: '998901112233', audiences: driver),
          isTrue);
    });

    test('«driver» хабар — йўловчига КЎРИНМАЙДИ', () {
      expect(
          news(audience: 'driver')
              .isVisibleTo(userId: '998901112233', audiences: passenger),
          isFalse);
    });

    test('«driver» хабар — ҳайдовчига кўринади', () {
      expect(
          news(audience: 'driver')
              .isVisibleTo(userId: '998901112233', audiences: driver),
          isTrue);
    });

    test('аудиториясиз (эски) ҳужжат — ҳаммага (орқага мослик)', () {
      expect(
          news(audience: '')
              .isVisibleTo(userId: '998901112233', audiences: passenger),
          isTrue);
    });

    test('шахсий хабар — фақат эгасига (аудиториядан қатъи назар)', () {
      final n = news(targetUserId: '998901112233');
      expect(n.isVisibleTo(userId: '998901112233', audiences: passenger),
          isTrue);
      expect(n.isVisibleTo(userId: '998909999999', audiences: passenger),
          isFalse);
    });
  });

  // Аудит O-4: илова умумий хабарларни `targetUserId == ''` билан сўрайди —
  // майдони йўқ ҳужжат бундай сўровга тушмайди.
  test('toCreateMap — умумий хабарда targetUserId бўш сатр (майдон бор)', () {
    final m = news().toCreateMap();
    expect(m.containsKey('targetUserId'), isTrue);
    expect(m['targetUserId'], '');
  });
}
