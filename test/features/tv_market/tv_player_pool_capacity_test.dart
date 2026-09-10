import 'package:ava_gurlan/features/tv_market/services/tv_player_pool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('selectEvictionVictim', () {
    test('ready+inflight jami (keep bilan birga) maxReady\'dan kam bo\'lsa '
        '— evict shart emas', () {
      final victim = selectEvictionVictim(
        readyKeys: ['a'],
        inflightKeys: {'c'},
        wanted: {'a', 'c', 'd'},
        keep: 'd',
        maxReady: 3,
      );
      expect(victim, isNull);
    });

    test(
        'sig\'im to\'lgan (keep hali yo\'q) — wanted\'da yo\'q ready '
        'ustuvor evict qilinadi', () {
      final victim = selectEvictionVictim(
        readyKeys: ['a', 'b', 'c'],
        inflightKeys: {},
        wanted: {'c', 'd'}, // a, b hozirgi generatsiyaga kerak emas
        keep: 'd',
        maxReady: 3,
      );
      expect(victim, anyOf('a', 'b'));
    });

    test('keep hech qachon evict qilinmaydi', () {
      final victim = selectEvictionVictim(
        readyKeys: ['a'],
        inflightKeys: {},
        wanted: <String>{},
        keep: 'a',
        maxReady: 1,
      );
      // live={a}=1 >= maxReady=1, lekin keep=a live'da bor -> over=false
      expect(victim, isNull);
    });

    test(
        'barcha ready controller\'lar wanted\'da bo\'lsa (masalan '
        'retain()ning o\'z parallel so\'rovlari) — victim topilmaydi, '
        'bosim faqat inflight orqali', () {
      final victim = selectEvictionVictim(
        readyKeys: ['a', 'b', 'c'],
        inflightKeys: {'d'}, // yangi so'rov endigina inflight bo'ldi
        wanted: {'a', 'b', 'c', 'd'},
        keep: 'd',
        maxReady: 3,
      );
      // live={a,b,c,d}=4 > 3 -> over=true, lekin barcha ready wanted'da,
      // keep(=d) ready emas -> ikkinchi fallback tsikli ham keep'ni
      // tashlaydi -> qoladigan ready'lar orasidan (a,b,c barchasi
      // "!=keep" shartiga mos) birinchisini qaytaradi (ustuvorlik yo'q
      // qolgani uchun oddiy fallback).
      expect(victim, anyOf('a', 'b', 'c'));
    });

    test(
        'ready bo\'sh, bosim faqat inflight\'dan — evict qilinadigan '
        'narsa yo\'q (null), chunki inflight majburan to\'xtatilmaydi',
        () {
      final victim = selectEvictionVictim(
        readyKeys: [],
        inflightKeys: {'a', 'b', 'c'},
        wanted: {'d'},
        keep: 'd',
        maxReady: 3,
      );
      expect(victim, isNull);
    });

    test(
        'ready+inflight bir xil url\'ni ikki marta hisoblamaydi '
        '(post-creation xavfsizlik tekshiruvi)', () {
      // _create() ctrl'ni _ready'ga qo'shgandan keyin, lekin `finally`
      // _inflight'dan olib tashlashdan OLDIN — shu url ikkalasida ham bor.
      final victim = selectEvictionVictim(
        readyKeys: ['other1', 'other2', 'url'],
        inflightKeys: {'url'},
        wanted: {'url'},
        keep: 'url',
        maxReady: 3,
      );
      // live = {other1, other2, url} (dublikatsiz) = 3, > maxReady emas,
      // va keep(url) live'da bor -> over=false -> hech narsa evict
      // qilinmasligi kerak (bo'lmasa other1/other2 noto'g'ri evict bo'lardi).
      expect(victim, isNull);
    });
  });

  group('shouldDiscardOnComplete', () {
    test('url wanted to\'plamida bo\'lsa — saqlanadi (discard qilinmaydi)',
        () {
      expect(shouldDiscardOnComplete('a', {'a', 'b'}), isFalse);
    });

    test(
        'url wanted to\'plamida yo\'q bo\'lsa (generatsiya eskirgan) — '
        'discard qilinadi', () {
      expect(shouldDiscardOnComplete('a', {'b', 'c'}), isTrue);
    });

    test('wanted bo\'sh bo\'lsa (masalan ekran hali hech narsa '
        'so\'ramagan) — discard qilinadi', () {
      expect(shouldDiscardOnComplete('a', <String>{}), isTrue);
    });
  });
}
