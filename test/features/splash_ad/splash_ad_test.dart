import 'dart:convert';
import 'dart:typed_data';

import 'package:ava_gurlan/core/widgets/app_launch_splash.dart';
import 'package:ava_gurlan/features/splash_ad/splash_ad.dart';
import 'package:ava_gurlan/features/splash_ad/splash_ad_actions.dart';
import 'package:ava_gurlan/features/splash_ad/splash_ad_cache.dart';
import 'package:ava_gurlan/features/splash_ad/splash_ad_prefetcher.dart';
import 'package:ava_gurlan/features/splash_ad/splash_ad_purchase_screen.dart';
import 'package:ava_gurlan/features/splash_ad/splash_ad_purchase_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemStore implements SplashAdStore {
  final Map<String, String> strings = {};
  final Map<String, Uint8List> images = {};
  int imageReads = 0;
  int legacyDeletes = 0;

  @override
  Future<String?> readString(String key) async => strings[key];

  @override
  Future<void> writeString(String key, String? value) async =>
      value == null ? strings.remove(key) : strings[key] = value;

  @override
  Future<Uint8List?> readImage(String adId) async {
    imageReads++;
    return images[adId];
  }

  @override
  Future<void> writeImage(String adId, Uint8List? bytes) async =>
      bytes == null ? images.remove(adId) : images[adId] = bytes;

  @override
  Future<void> deleteLegacy() async => legacyDeletes++;
}

// 1×1 шаффоф PNG.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

final _now = DateTime.utc(2026, 11, 28, 7); // Тошкент 12:00
const _img = 'https://firebasestorage.googleapis.com/x';

SplashAd _ad({
  String id = 'ad1',
  String imageUrl = '',
  Map<String, String> text = const {'uz_Cyrl': 'Гурлан нон'},
  List<String> districts = const [],
  List<String> regionIds = const [],
  int weight = 1,
  DateTime? start,
  DateTime? end,
  String linkUrl = '',
}) =>
    SplashAd(
      id: id,
      version: 1,
      text: text,
      imageUrl: imageUrl,
      linkUrl: linkUrl,
      startAt: start ?? _now.subtract(const Duration(days: 1)),
      endAt: end ?? _now.add(const Duration(days: 1)),
      districts: districts,
      regionIds: regionIds,
      weight: weight,
    );

Widget _app({
  SplashAdLaunch? launch,
  String lang = 'uz_Cyrl',
  VoidCallback? onFinished,
  VoidCallback? onAdvertise,
  ValueChanged<SplashAd>? onShown,
  ValueChanged<SplashAd>? onOpenAd,
}) =>
    AppLaunchSplash(
      launch: launch,
      lang: lang,
      onFinished: onFinished,
      onAdvertise: onAdvertise,
      onShown: onShown,
      onOpenAd: onOpenAd,
      child: const MaterialApp(home: Scaffold(body: Text('HOME'))),
    );

/// Сохта сервер хизмати (нарх — серверники каби: кунлик × туманлар × кун).
class _FakeBuy extends SplashAdPurchaseService {
  _FakeBuy({this.available = true, this.balance = 500000, this.priceChangeOnce = false});

  final bool available;
  int balance;
  bool priceChangeOnce;
  int perDistrict = 20000;
  final quotes = <SplashAdPurchaseRequest>[];
  final purchases = <(SplashAdPurchaseRequest, int)>[];
  final uploads = <String>[];

  @override
  Future<SplashAdPurchaseInfo> getInfo() async => SplashAdPurchaseInfo(
        available: available,
        perDay: const {'district': 20000, 'region': 60000, 'republic': 150000},
        tariffVersion: 2,
        balance: balance,
        maxDistricts: 10,
        today: '2026-11-28',
      );

  int _amount(SplashAdPurchaseRequest r) {
    final per = switch (r.areaLevel) { 'district' => perDistrict * r.districts.length, 'region' => 60000, _ => 150000 };
    return per * r.days;
  }

  @override
  Future<SplashAdQuote> quote(SplashAdPurchaseRequest r) async {
    quotes.add(r);
    final a = _amount(r);
    return SplashAdQuote(amount: a, pricePerDay: a ~/ r.days, balance: balance, sufficient: a <= balance, tariffVersion: 2);
  }

  @override
  Future<String> purchase(SplashAdPurchaseRequest r, {required int expectedAmount}) async {
    purchases.add((r, expectedAmount));
    if (priceChangeOnce) {
      priceChangeOnce = false;
      perDistrict = 25000;
      throw const SplashAdPurchaseError('PRICE_CHANGED');
    }
    balance -= expectedAmount;
    return 'sa_order';
  }

  @override
  Future<List<SplashAdOrderView>> myOrders() async => const [];

  @override
  Future<String> uploadImage({required String ownerPhone, required XFile image}) async {
    uploads.add(ownerPhone);
    return 'https://firebasestorage.googleapis.com/v0/b/x/o/ads%2F$ownerPhone%2Fa.jpg';
  }
}

class _FakeAreas implements SplashAreaSource {
  @override
  Future<List<({String id, String name})>> regions(String lang) async => const [(id: 'xorazm', name: 'Хоразм')];

  @override
  Future<List<({String id, String name})>> districts(String regionId, String lang) async =>
      const [(id: 'gurlan', name: 'Гурлан'), (id: 'urganch', name: 'Урганч')];
}

void main() {
  group('AppLaunchSplash — 3 с (эга 2026-11-28), ўтказиш йўқ, «Реклама бериш»', () {
    testWidgets('аниқ 3 сония кўринади, кейин бир марта onFinished', (t) async {
      var finished = 0;
      await t.pumpWidget(_app(onFinished: () => finished++));
      expect(AppLaunchSplash.displayDuration, const Duration(seconds: 3));
      expect(find.byKey(AppLaunchSplash.overlayKey), findsOneWidget);
      await t.pump(const Duration(milliseconds: 2999));
      expect(find.byKey(AppLaunchSplash.overlayKey), findsOneWidget);
      expect(finished, 0);
      await t.pump(const Duration(milliseconds: 1));
      expect(find.byKey(AppLaunchSplash.overlayKey), findsNothing);
      expect(finished, 1);
      await t.pump(const Duration(seconds: 5));
      expect(finished, 1);
    });

    testWidgets('сукут матни + «Реклама бериш»; ўтказиш тугмаси йўқ, фонни босиш ёпмайди', (t) async {
      await t.pumpWidget(_app());
      expect(find.text('Бу ерда сизнинг рекламангиз бўлиши мумкин'), findsOneWidget);
      expect(find.text('Реклама бериш'), findsOneWidget);
      for (final s in ['Ўтказиб юбориш', 'O\'tkazib yuborish', 'Пропустить', 'Skip']) {
        expect(find.textContaining(s), findsNothing);
      }
      expect(find.byType(CloseButton), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
      await t.tap(find.byKey(AppLaunchSplash.placeholderKey));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byKey(AppLaunchSplash.overlayKey), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
    });

    testWidgets('«Реклама бериш» — splash дарров ёпилади ва onAdvertise чақирилади', (t) async {
      var adv = 0, finished = 0;
      await t.pumpWidget(_app(onAdvertise: () => adv++, onFinished: () => finished++));
      await t.tap(find.byKey(AppLaunchSplash.advertiseKey));
      await t.pump();
      expect(adv, 1);
      expect(finished, 1);
      expect(find.byKey(AppLaunchSplash.overlayKey), findsNothing);
      await t.pump(const Duration(seconds: 3));
      expect(finished, 1);
    });

    testWidgets('3 тил: лотин (янги ҳарфлар) ва рус', (t) async {
      await t.pumpWidget(_app(lang: 'uz_Latn'));
      expect(find.text('Bu yerda sizning reklamangiz bölişi mumkin'), findsOneWidget);
      expect(find.text('Reklama beriş'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(_app(lang: 'ru'));
      expect(find.text('Здесь может быть ваша реклама'), findsOneWidget);
      expect(find.text('Разместить рекламу'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
    });

    testWidgets('кешдаги креатив: расм + «Реклама» белгиси, onShown бир марта; ҳавола босилса ёпилади', (t) async {
      final shown = <String>[];
      SplashAd? opened;
      final ad = _ad(imageUrl: _img, linkUrl: 'https://ava.uz');
      await t.pumpWidget(_app(
        launch: SplashAdLaunch(ad: ad, imageBytes: _png),
        onShown: (a) => shown.add(a.id),
        onOpenAd: (a) => opened = a,
      ));
      await t.pump();
      expect(find.byKey(AppLaunchSplash.imageKey), findsOneWidget);
      expect(find.text('Реклама'), findsOneWidget);
      expect(shown, ['ad1']);
      await t.tap(find.byKey(AppLaunchSplash.imageKey));
      await t.pump();
      expect(opened?.id, 'ad1');
      expect(find.byKey(AppLaunchSplash.overlayKey), findsNothing);
      expect(shown, ['ad1']);
    });

    testWidgets('матнли креатив (лотин автоматик)', (t) async {
      await t.pumpWidget(_app(launch: SplashAdLaunch(ad: _ad()), lang: 'uz_Latn'));
      expect(find.byKey(AppLaunchSplash.textKey), findsOneWidget);
      expect(find.text('Gurlan non'), findsOneWidget);
      await t.pump(const Duration(seconds: 3));
    });
  });

  group('SplashAd — сана ва ҳудуд', () {
    test('туман: бўш — ҳамма; рўйхат — фақат мос туман, номаълум туман — йўқ', () {
      expect(_ad().isEligible(_now, ''), isTrue);
      final g = _ad(districts: const ['gurlan']);
      expect(g.isEligible(_now, 'gurlan'), isTrue);
      expect(g.isEligible(_now, 'urganch'), isFalse);
      expect(g.isEligible(_now, ''), isFalse);
    });

    test('вилоят даражаси: вилоятдаги ҳар туман; бошқа вилоят — йўқ; туман ёки вилоят мос бўлса етарли', () {
      final r = _ad(regionIds: const ['xorazm']);
      expect(r.isEligible(_now, 'gurlan', 'xorazm'), isTrue);
      expect(r.isEligible(_now, 'yunusobod', 'toshkent'), isFalse);
      expect(r.isEligible(_now, 'gurlan', ''), isFalse);
      final both = _ad(districts: const ['chilonzor'], regionIds: const ['xorazm']);
      expect(both.isEligible(_now, 'chilonzor', 'toshkent'), isTrue);
      expect(SplashAd.areaQueryKeys('gurlan', 'xorazm'), ['all', 'd:gurlan', 'r:xorazm']);
      expect(SplashAd.areaQueryKeys('', ''), ['all']);
    });

    test('сана ойнаси: start ≤ now < end (чегара)', () {
      final a = _ad(start: _now, end: _now.add(const Duration(hours: 1)));
      expect(a.isInWindow(_now), isTrue);
      expect(a.isInWindow(_now.subtract(const Duration(milliseconds: 1))), isFalse);
      expect(a.isInWindow(_now.add(const Duration(hours: 1))), isFalse);
      expect(const SplashAd(id: 'x', version: 1).isInWindow(_now), isFalse);
    });

    test('selectForCache: ҳудуд, тугаганлар ташланади, 2 кун ичида бошланадиганлар олинади, оғирлик тартиби, чегара', () {
      final out = SplashAd.selectForCache([
        _ad(id: 'low', weight: 1),
        _ad(id: 'other', weight: 99, districts: const ['urganch']),
        _ad(id: 'big', weight: 50),
        _ad(id: 'old', weight: 90, end: _now.subtract(const Duration(minutes: 1))),
        _ad(id: 'soon', weight: 10, start: _now.add(const Duration(days: 1)), end: _now.add(const Duration(days: 3))),
        _ad(id: 'late', weight: 10, start: _now.add(const Duration(days: 5)), end: _now.add(const Duration(days: 7))),
        _ad(id: 'empty', text: const {}),
      ], _now, 'gurlan', 'xorazm');
      expect(out.map((a) => a.id), ['big', 'soon', 'low']);
      final many = [for (var i = 0; i < 12; i++) _ad(id: 'a$i', weight: i + 1)];
      expect(SplashAd.selectForCache(many, _now, '', '', max: 8).length, 8);
    });

    test('эски ҳужжат (weight йўқ) — оғирлик 1', () {
      expect(SplashAd.fromCacheMap({'id': 'x', 'startAt': 1, 'endAt': 2})!.weight, 1);
      expect(SplashAd.fromCacheMap({'id': 'x', 'weight': 0})!.weight, 1);
    });
  });

  group('SplashAdRotation — оғирлик бўйича навбат (smooth weighted round-robin)', () {
    List<String> run(List<SplashAd> ads, int n) {
      var state = <String, int>{};
      final out = <String>[];
      for (var i = 0; i < n; i++) {
        final (ad, next) = SplashAdRotation.next(ads, state);
        state = next;
        out.add(ad!.id);
      }
      return out;
    }

    test('тенг оғирлик — кетма-кет очилишлар ҳар хил (алмашиб)', () {
      final seq = run([_ad(id: 'a'), _ad(id: 'b'), _ad(id: 'c')], 9);
      for (var i = 1; i < seq.length; i++) {
        expect(seq[i], isNot(seq[i - 1]), reason: 'open $i');
      }
      expect(seq.where((x) => x == 'a').length, 3);
    });

    test('улуш тўлов миқдорига пропорционал: 40000 : 20000 : 20000 → 2 : 1 : 1', () {
      final seq = run([_ad(id: 'big', weight: 40000), _ad(id: 'm1', weight: 20000), _ad(id: 'm2', weight: 20000)], 400);
      expect(seq.where((x) => x == 'big').length, 200);
      expect(seq.where((x) => x == 'm1').length, 100);
      expect(seq.where((x) => x == 'm2').length, 100);
      // ҳар 4 очилишда (бир цикл) аниқ 2 : 1 : 1
      expect(seq.take(4).toSet(), {'big', 'm1', 'm2'});
    });

    test('3 : 1 — 40 очилишда аниқ 30 : 10', () {
      final seq = run([_ad(id: 'a', weight: 3), _ad(id: 'b', weight: 1)], 40);
      expect(seq.where((x) => x == 'a').length, 30);
      expect(seq.where((x) => x == 'b').length, 10);
    });

    test('номзод йўқ — null; эскирган ҳолат калитлари ташланади', () {
      expect(SplashAdRotation.next(const [], const {'x': 5}).$1, isNull);
      final (_, s) = SplashAdRotation.next([_ad(id: 'a')], const {'gone': 7});
      expect(s.keys, ['a']);
    });
  });

  group('SplashAdCache — фақат кеш, ҲАР очилишда реклама', () {
    Future<SplashAdCache> seeded(List<SplashAdCached> items, {Map<String, Uint8List> images = const {}}) async {
      final cache = SplashAdCache(store: _MemStore());
      await cache.saveAll(items, images: images);
      return cache;
    }

    test('очилиш тармоқсиз: кешдаги креатив ва расм', () async {
      final store = _MemStore();
      final cache = SplashAdCache(store: store);
      expect(await cache.loadForLaunch(now: _now, districtId: 'gurlan'), isNull);
      await cache.saveAll([SplashAdCached(_ad(imageUrl: _img), imageCached: true)], images: {'ad1': _png});
      final l = await cache.loadForLaunch(now: _now, districtId: 'gurlan');
      expect(l?.ad.id, 'ad1');
      expect(l?.imageBytes, _png);
      expect(store.legacyDeletes, 1, reason: 'эски v1 кеш тозаланади');
    });

    test('расм кешда йўқ — матн бўлса матн, бўлмаса сукут', () async {
      final cache = await seeded([SplashAdCached(_ad(imageUrl: _img))]);
      final l = await cache.loadForLaunch(now: _now, districtId: '');
      expect(l?.imageBytes, isNull);
      expect(l?.ad.id, 'ad1');
      final noText = await seeded([SplashAdCached(_ad(imageUrl: _img, text: const {}))]);
      expect(await noText.loadForLaunch(now: _now, districtId: ''), isNull);
    });

    test('мос эмас ҳудуд/муддат — сукут', () async {
      final cache = await seeded([
        SplashAdCached(_ad(districts: const ['gurlan'])),
        SplashAdCached(_ad(id: 'r', regionIds: const ['xorazm'])),
      ]);
      expect(await cache.loadForLaunch(now: _now, districtId: 'yunusobod', regionId: 'toshkent'), isNull);
      expect(await cache.loadForLaunch(now: _now.add(const Duration(days: 2)), districtId: 'gurlan'), isNull);
      expect((await cache.loadForLaunch(now: _now, districtId: 'xiva', regionId: 'xorazm'))?.ad.id, 'r');
    });

    test('ҲАР очилишда реклама (3/кун чегараси йўқ): 20 очилиш — 20 реклама; кетма-кет турлиси', () async {
      final cache = await seeded([SplashAdCached(_ad(id: 'a')), SplashAdCached(_ad(id: 'b'))]);
      String? prev;
      for (var i = 0; i < 20; i++) {
        final l = await cache.loadForLaunch(now: _now, districtId: '');
        expect(l, isNotNull, reason: 'open $i');
        expect(l!.ad.id, isNot(prev), reason: 'open $i');
        prev = l.ad.id;
        await cache.recordImpression(l.ad.id, _now);
      }
      final p = await cache.pendingBefore(_now.add(const Duration(days: 1)));
      expect(p[SplashAdCache.dayKey(_now)], {'a': 10, 'b': 10});
    });

    test('оғирлик (кунлик тўлов) бўйича улуш сақланади ва ҳолат қурилмада қолади (янги экземпляр)', () async {
      final store = _MemStore();
      await SplashAdCache(store: store).saveAll([
        SplashAdCached(_ad(id: 'paid', weight: 60000)),
        SplashAdCached(_ad(id: 'small', weight: 20000)),
      ]);
      final counts = <String, int>{};
      for (var i = 0; i < 40; i++) {
        // ҳар очилиш — янги илова жараёни (ҳолат фақат store'да)
        final l = await SplashAdCache(store: store).loadForLaunch(now: _now, districtId: '');
        counts[l!.ad.id] = (counts[l.ad.id] ?? 0) + 1;
      }
      expect(counts, {'paid': 30, 'small': 10});
    });

    test('йиғма: фақат бугундан олдинги кунлар юборилади', () async {
      final cache = SplashAdCache(store: _MemStore());
      final yesterday = _now.subtract(const Duration(days: 1));
      await cache.recordImpression('ad1', yesterday);
      await cache.recordImpression('ad1', yesterday);
      await cache.recordImpression('ad1', _now);
      final p = await cache.pendingBefore(_now);
      expect(p, {
        SplashAdCache.dayKey(yesterday): {'ad1': 2},
      });
      await cache.clearPending(p.keys);
      expect(await cache.pendingBefore(_now), isEmpty);
      expect(await cache.pendingBefore(_now.add(const Duration(days: 1))), {
        SplashAdCache.dayKey(_now): {'ad1': 1},
      });
    });

    test('рўйхатдан чиққан реклама расми ўчирилади', () async {
      final store = _MemStore();
      final cache = SplashAdCache(store: store);
      await cache.saveAll([SplashAdCached(_ad(id: 'x', imageUrl: _img), imageCached: true)], images: {'x': _png});
      expect(store.images.keys, ['x']);
      await cache.saveAll([SplashAdCached(_ad(id: 'y'))]);
      expect(store.images, isEmpty);
      await cache.clear();
      expect(await cache.cached(), isEmpty);
    });

    test('Тошкент санаси (UTC+5)', () {
      expect(SplashAdCache.dayKey(DateTime.utc(2026, 11, 27, 19, 1)), '2026-11-28');
      expect(SplashAdCache.dayKey(DateTime.utc(2026, 11, 27, 18, 59)), '2026-11-27');
    });
  });

  group('SplashAdPrefetcher — кейинги очилишлар учун, ҳудуд бўйича, ҳажм чегараси', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('бир нечта креатив ва расмлар кешланади; статистика бир чақирувда; ҳудуд калитлари узатилади', () async {
      final cache = SplashAdCache(store: _MemStore());
      await cache.recordImpression('ad1', _now.subtract(const Duration(days: 1)));
      final sent = <Map<String, Map<String, int>>>[];
      final asked = <String>[];
      var downloads = 0;
      final p = SplashAdPrefetcher(
        cache: cache,
        now: () => _now,
        fetchAds: (d, r) async {
          asked.add('$d/$r');
          return [
            _ad(id: 'a', imageUrl: _img, districts: const ['gurlan'], weight: 3),
            _ad(id: 'b', imageUrl: '$_img/b', regionIds: const ['xorazm'], weight: 1),
            _ad(id: 'c', districts: const ['xiva']),
          ];
        },
        download: (_) async {
          downloads++;
          return _png;
        },
        sendStats: (d) async => sent.add(d),
      );
      await p.run(districtId: 'gurlan', regionId: 'xorazm');
      expect(asked, ['gurlan/xorazm']);
      expect(sent.length, 1);
      expect(await cache.pendingBefore(_now), isEmpty);
      final c = await cache.cached();
      expect(c.map((x) => x.ad.id), ['a', 'b']);
      expect(c.every((x) => x.imageCached), isTrue);
      expect((await cache.loadForLaunch(now: _now, districtId: 'gurlan', regionId: 'xorazm'))?.imageBytes, _png);
      // 3 соат ичида қайта — тармоққа чиқмайди; кейин force — ўзгармаган расм қайта юкланмайди.
      await p.run(districtId: 'gurlan', regionId: 'xorazm');
      expect(downloads, 2);
      await p.refresh(districtId: 'gurlan', regionId: 'xorazm', force: true);
      expect(downloads, 2);
      expect(sent.length, 1);
    });

    test('ҳажм чегараси: сиғмаган расмли реклама — матни бўлса матн билан, бўлмаса ташланади', () async {
      final cache = SplashAdCache(store: _MemStore());
      final big = Uint8List(600);
      final p = SplashAdPrefetcher(
        cache: cache,
        now: () => _now,
        maxCacheBytes: 1000,
        fetchAds: (_, __) async => [
          _ad(id: 'a', imageUrl: '$_img/a', weight: 3),
          _ad(id: 'b', imageUrl: '$_img/b', weight: 2),
          _ad(id: 'c', imageUrl: '$_img/c', weight: 1, text: const {}),
        ],
        download: (_) async => big,
        sendStats: (_) async {},
      );
      await p.run(districtId: '');
      final c = {for (final x in await cache.cached()) x.ad.id: x.imageCached};
      expect(c, {'a': true, 'b': false});
    });

    test('статистика юборилмаса — йиғма сақланади; мос реклама йўқ — кеш тозаланади', () async {
      final cache = SplashAdCache(store: _MemStore());
      await cache.saveAll([SplashAdCached(_ad())]);
      await cache.recordImpression('ad1', _now.subtract(const Duration(days: 1)));
      final p = SplashAdPrefetcher(
        cache: cache,
        now: () => _now,
        fetchAds: (_, __) async => [_ad(districts: const ['xiva'])],
        download: (_) async => null,
        sendStats: (_) async => throw Exception('offline'),
      );
      await p.run(districtId: 'gurlan');
      expect((await cache.pendingBefore(_now)).length, 1);
      expect(await cache.loadForLaunch(now: _now, districtId: 'gurlan'), isNull);
    });
  });

  group('«Реклама бериш» йўли', () {
    test('кирган — харид оқими; кирмаган — рўйхатдан ўтиш хабари', () {
      expect(splashAdvertiseTargetFor(phone: '+998 90 123 45 67', signedIn: true), SplashAdvertiseTarget.purchase);
      expect(splashAdvertiseTargetFor(phone: '998901234567', signedIn: false), SplashAdvertiseTarget.needLogin);
      expect(splashAdvertiseTargetFor(phone: '', signedIn: true), SplashAdvertiseTarget.needLogin);
    });

    testWidgets('харид экрани очилади; харид ёпиқ бўлса — «Админ билан чат» тайёр матн билан', (t) async {
      final key = GlobalKey<NavigatorState>();
      String? phone, chat, draft;
      await t.pumpWidget(MaterialApp(navigatorKey: key, home: const Scaffold(body: Text('HOME'))));
      final f = openSplashAdvertise(
        key.currentState!,
        lang: 'uz_Cyrl',
        readPhone: () async => '901234567',
        isSignedIn: () => true,
        purchaseBuilder: (p, onChat) {
          phone = p;
          return SplashAdPurchaseScreen(ownerPhone: p, service: _FakeBuy(available: false), areas: _FakeAreas(), onAdminChat: onChat);
        },
        chatBuilder: (id, d) {
          chat = id;
          draft = d;
          return const Scaffold(body: Text('CHAT'));
        },
      );
      await t.pumpAndSettle();
      expect(phone, '998901234567');
      expect(find.text(SplashBuyTexts.of('notAvailable', 'uz_Cyrl')), findsOneWidget);
      await t.tap(find.text(SplashBuyTexts.of('adminChat', 'uz_Cyrl')));
      await t.pumpAndSettle();
      expect(find.text('CHAT'), findsOneWidget);
      expect(chat, '998901234567');
      expect(draft, SplashAdTexts.chatDraft('uz_Cyrl'));
      key.currentState!.pop();
      await t.pumpAndSettle();
      key.currentState!.pop();
      await t.pumpAndSettle();
      await f;
    });
  });

  group('SplashAdPurchaseScreen — харид оқими', () {
    Future<_FakeBuy> open(WidgetTester t, _FakeBuy svc, {Future<XFile?> Function()? pick}) async {
      await t.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
        home: SplashAdPurchaseScreen(
          ownerPhone: '998901234567',
          service: svc,
          areas: _FakeAreas(),
          initialRegionId: 'xorazm',
          initialDistrictId: 'gurlan',
          pickImage: pick,
          myAdsBuilder: (_) => const Scaffold(body: Text('MY ADS')),
        ),
      ));
      await t.pumpAndSettle();
      return svc;
    }

    testWidgets('3 кун × 2 туман: сервер нархи → тасдиқ → ҳамёндан тўлов (expectedAmount) → «Менинг рекламаларим»', (t) async {
      final svc = await open(t, _FakeBuy());
      await t.tap(find.text('3 кун'));
      await t.tap(find.text('Урганч'));
      await t.enterText(find.byKey(SplashAdPurchaseScreen.textKey), 'Гурлан нон');
      await t.pump();
      await t.tap(find.byKey(SplashAdPurchaseScreen.quoteKey));
      await t.pumpAndSettle();
      expect(svc.quotes.single.districts, ['gurlan', 'urganch']);
      expect(svc.quotes.single.days, 3);
      expect(svc.quotes.single.startDay, '2026-11-28');
      expect(find.textContaining('120 000'), findsWidgets);
      await t.tap(find.byKey(SplashAdPurchaseScreen.payKey));
      await t.pumpAndSettle();
      expect(svc.purchases.single.$2, 120000);
      expect(svc.purchases.single.$1.text, 'Гурлан нон');
      expect(find.text('MY ADS'), findsOneWidget);
    });

    testWidgets('маблағ етмаса — тўлов тугмаси ўчиқ, тўлов чақирилмайди', (t) async {
      final svc = await open(t, _FakeBuy(balance: 1000));
      await t.enterText(find.byKey(SplashAdPurchaseScreen.textKey), 'Нон');
      await t.tap(find.byKey(SplashAdPurchaseScreen.quoteKey));
      await t.pumpAndSettle();
      expect(find.text(SplashBuyTexts.of('insufficient', 'uz_Cyrl')), findsOneWidget);
      final btn = t.widget<FilledButton>(find.byKey(SplashAdPurchaseScreen.payKey));
      expect(btn.onPressed, isNull);
      expect(svc.purchases, isEmpty);
    });

    testWidgets('нарх ўзгарса — янги нарх кўрсатилади; қайта тўлов ЎША clientRequestId билан (идемпотент)', (t) async {
      final svc = await open(t, _FakeBuy(priceChangeOnce: true));
      await t.enterText(find.byKey(SplashAdPurchaseScreen.textKey), 'Нон');
      await t.tap(find.byKey(SplashAdPurchaseScreen.quoteKey));
      await t.pumpAndSettle();
      await t.tap(find.byKey(SplashAdPurchaseScreen.payKey));
      await t.pumpAndSettle();
      expect(find.textContaining('25 000'), findsWidgets);
      await t.tap(find.byKey(SplashAdPurchaseScreen.payKey));
      await t.pumpAndSettle();
      expect(svc.purchases.length, 2);
      expect(svc.purchases[0].$1.clientRequestId, svc.purchases[1].$1.clientRequestId);
      expect(svc.purchases[1].$2, 25000);
      expect(find.text('MY ADS'), findsOneWidget);
    });

    testWidgets('мазмунсиз — нарх сўралмайди; расм танланса — ўз папкасига юкланади (бир марта)', (t) async {
      final svc = await open(t, _FakeBuy(), pick: () async => XFile.fromData(_png, name: 'a.png'));
      await t.tap(find.byKey(SplashAdPurchaseScreen.quoteKey));
      await t.pump();
      expect(find.text(SplashBuyTexts.of('needContent', 'uz_Cyrl')), findsOneWidget);
      expect(svc.quotes, isEmpty);
      // Эга 2026-11-28: креатив талаби расм танлаш ёнида.
      expect(find.byKey(SplashAdPurchaseScreen.creativeSpecKey), findsOneWidget);
      expect(find.text(SplashAdTexts.creativeSpec('uz_Cyrl')), findsOneWidget);
      await t.pumpAndSettle();
      await t.tap(find.text(SplashBuyTexts.of('image', 'uz_Cyrl')));
      await t.pumpAndSettle();
      await t.tap(find.text(SplashBuyTexts.of('republic', 'uz_Cyrl')));
      await t.tap(find.byKey(SplashAdPurchaseScreen.quoteKey));
      await t.pumpAndSettle();
      expect(svc.uploads, ['998901234567']);
      expect(svc.quotes.single.areaLevel, 'republic');
      expect(svc.quotes.single.imageUrl, contains('ads%2F998901234567%2F'));
      await t.tap(find.text(SplashBuyTexts.of('cancel', 'uz_Cyrl')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(SplashAdPurchaseScreen.quoteKey));
      await t.pumpAndSettle();
      expect(svc.uploads.length, 1, reason: 'расм қайта юкланмайди');
    });
  });

  group('«Менинг рекламаларим»', () {
    const base = SplashAdOrderView(orderId: 'o', status: 'approved', days: 3, startDay: '2026-11-27', endDay: '2026-11-29', areaLevel: 'district');
    test('ҳолат сана бўйича', () {
      String k(SplashAdOrderView o, String d) => MySplashAdsScreenStatus.of(o, d);
      expect(k(base, '2026-11-28'), 'active');
      expect(k(base, '2026-11-26'), 'scheduled');
      expect(k(base, '2026-11-30'), 'ended');
      expect(k(const SplashAdOrderView(orderId: 'o', status: 'pending', days: 1, startDay: '', endDay: '', areaLevel: ''), '2026-11-28'), 'pending');
      expect(k(const SplashAdOrderView(orderId: 'o', status: 'rejected', days: 1, startDay: '', endDay: '', areaLevel: ''), '2026-11-28'), 'rejected');
    });
  });
}
