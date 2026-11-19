import 'package:ava_gurlan/features/tv_market/models/tv_clip.dart';
import 'package:ava_gurlan/features/tv_market/utils/tv_news_window.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Эга қарори 2026-11-19: AVAGram таблари — 0 «AVAGram», 1 «Кун янгиликлари», 2 «Реклама ва Эълонлар».
/// Янгилик 24 соат; товар/хизмат (реклама эмас) фаоллашгандан кейинги 24 соат ФАҚАТ «Кун янгиликлари»да,
/// кейин AVAGram'да. Ҳисоб сервер `activatedAt`идан; у йўқ эски ҳужжат — «эски» (AVAGram).
TvClip _clip(
  String id, {
  String category = 'product',
  String status = 'active',
  DateTime? createdAt,
  DateTime? activatedAt,
  int? activatedAtMs,
  String adTier = '',
}) =>
    TvClip.fromMap(id, {
      'videoUrl': 'https://x/v.mp4',
      'posterUrl': 'https://x/p.jpg',
      'title': id,
      'category': category,
      'status': status,
      'ownerPhone': '998901112233',
      'districtId': 'gurlan',
      if (adTier.isNotEmpty) 'adTier': adTier,
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt),
      if (activatedAt != null) 'activatedAt': Timestamp.fromDate(activatedAt),
      if (activatedAtMs != null) 'activatedAtMs': activatedAtMs,
    });

void main() {
  final now = DateTime.utc(2026, 11, 19, 12);
  DateTime ago(Duration d) => now.subtract(d);
  const h = Duration(hours: 1);
  const m = Duration(minutes: 1);

  group('TvClip.activatedAt', () {
    test('Firestore Timestamp ва CDN JSON (activatedAtMs) дан ўқилади', () {
      expect(_clip('a', activatedAt: ago(h)).activatedAt!.isAtSameMomentAs(ago(h)), isTrue);
      final ms = ago(h).millisecondsSinceEpoch;
      expect(_clip('b', activatedAtMs: ms).activatedAt!.millisecondsSinceEpoch, ms);
      expect(_clip('c').activatedAt, isNull);
    });

    test('toMap activatedAt ёзмайди (қоида клиентга тақиқлайди)', () {
      expect(_clip('a', activatedAt: ago(h)).toMap().containsKey('activatedAt'), isFalse);
    });

    test('shownAt = activatedAt ?? createdAt', () {
      expect(tvClipShownAt(_clip('a', createdAt: ago(h * 3), activatedAt: ago(h)))!.isAtSameMomentAs(ago(h)), isTrue);
      expect(tvClipShownAt(_clip('b', createdAt: ago(h * 3)))!.isAtSameMomentAs(ago(h * 3)), isTrue);
    });
  });

  group('tvClipIsFreshNonNews — чегаралар', () {
    test('23:59 — янги; 24:00 ва 24:01 — эски', () {
      expect(tvClipIsFreshNonNews(_clip('a', activatedAt: ago(const Duration(hours: 24) - m)), now), isTrue);
      expect(tvClipIsFreshNonNews(_clip('b', activatedAt: ago(const Duration(hours: 24))), now), isFalse);
      expect(tvClipIsFreshNonNews(_clip('c', activatedAt: ago(const Duration(hours: 24) + m)), now), isFalse);
    });

    test('хизмат ҳам янги; реклама (ad) ва янгилик (news) — бу рўйхатда эмас', () {
      expect(tvClipIsFreshNonNews(_clip('s', category: 'service', activatedAt: ago(h)), now), isTrue);
      expect(tvClipIsFreshNonNews(_clip('ad', category: 'ad', activatedAt: ago(h)), now), isFalse);
      expect(tvClipIsFreshNonNews(_clip('n', category: 'news', activatedAt: ago(h)), now), isFalse);
    });

    test('activatedAt йўқ (эски ҳужжат) — эски, createdAt янги бўлса ҳам', () {
      expect(tvClipIsFreshNonNews(_clip('legacy', createdAt: ago(h)), now), isFalse);
    });

    test('фаол эмас — янги эмас', () {
      expect(tvClipIsFreshNonNews(_clip('p', status: 'pending', activatedAt: ago(h)), now), isFalse);
    });
  });

  group('tvClipInFeedTab', () {
    final fresh = _clip('fresh', activatedAt: ago(h));
    final old = _clip('old', activatedAt: ago(h * 25));
    final legacy = _clip('legacy', createdAt: ago(h));
    final news = _clip('news', category: 'news', activatedAt: ago(h));
    final ad = _clip('ad', category: 'ad', activatedAt: ago(h));

    test('AVAGram (0): янги товар ЙЎҚ; эски, эски ҳужжат, янгилик, реклама — бор', () {
      expect(tvClipInFeedTab(fresh, kTvTabAll, now), isFalse);
      for (final c in [old, legacy, news, ad]) {
        expect(tvClipInFeedTab(c, kTvTabAll, now), isTrue, reason: c.id);
      }
    });

    test('Кун янгиликлари (1): янгилик + янги товар; эски, реклама, эски ҳужжат — йўқ', () {
      expect(tvClipInFeedTab(news, kTvTabNews, now), isTrue);
      expect(tvClipInFeedTab(fresh, kTvTabNews, now), isTrue);
      for (final c in [old, ad, legacy]) {
        expect(tvClipInFeedTab(c, kTvTabNews, now), isFalse, reason: c.id);
      }
    });

    test('Реклама ва Эълонлар (2): ўзгармаган — товар/хизмат/реклама (янгиси ҳам), янгилик йўқ', () {
      for (final c in [fresh, old, legacy, ad]) {
        expect(tvClipInFeedTab(c, kTvTabMarket, now), isTrue, reason: c.id);
      }
      expect(tvClipInFeedTab(news, kTvTabMarket, now), isFalse);
    });

    test("24 соат ўтгач товар янгиликлардан AVAGram'га ўтади (23:59 / 24:01)", () {
      final a = _clip('a', activatedAt: ago(const Duration(hours: 24) - m));
      final b = _clip('b', activatedAt: ago(const Duration(hours: 24) + m));
      expect(tvClipInFeedTab(a, kTvTabNews, now) && !tvClipInFeedTab(a, kTvTabAll, now), isTrue);
      expect(!tvClipInFeedTab(b, kTvTabNews, now) && tvClipInFeedTab(b, kTvTabAll, now), isTrue);
    });
  });

  group('tvMergeNewsTab', () {
    test('янгилик + янги товар бирлашади, такрор йўқ, эскирганлар тушади', () {
      final news = _clip('n1', category: 'news', activatedAt: ago(h));
      final fresh = _clip('f1', activatedAt: ago(h * 2));
      final stale = _clip('f2', activatedAt: ago(h * 30));
      final out = tvMergeNewsTab([news, fresh], [fresh, stale], now);
      expect(out.map((c) => c.id).toSet(), {'n1', 'f1'});
      expect(out.length, 2);
    });
  });
}
