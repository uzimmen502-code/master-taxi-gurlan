import 'dart:convert';
import 'dart:typed_data';

import 'package:ava_gurlan/core/widgets/app_launch_splash.dart';
import 'package:ava_gurlan/features/splash_ad/splash_ad.dart';
import 'package:ava_gurlan/features/splash_ad/splash_ad_actions.dart';
import 'package:ava_gurlan/features/splash_ad/splash_ad_cache.dart';
import 'package:ava_gurlan/features/splash_ad/splash_ad_prefetcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemStore implements SplashAdStore {
  final Map<String, String> strings = {};
  Uint8List? image;
  int imageReads = 0;

  @override
  Future<String?> readString(String key) async => strings[key];

  @override
  Future<void> writeString(String key, String? value) async =>
      value == null ? strings.remove(key) : strings[key] = value;

  @override
  Future<Uint8List?> readImage() async {
    imageReads++;
    return image;
  }

  @override
  Future<void> writeImage(Uint8List? bytes) async => image = bytes;
}

// 1×1 шаффоф PNG.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

final _now = DateTime.utc(2026, 11, 28, 7); // Тошкент 12:00

SplashAd _ad({
  String id = 'ad1',
  String imageUrl = '',
  Map<String, String> text = const {'uz_Cyrl': 'Гурлан нон'},
  List<String> districts = const [],
  int priority = 0,
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
      priority: priority,
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

void main() {
  group('AppLaunchSplash — 2 с, ўтказиш йўқ, «Реклама бериш»', () {
    testWidgets('аниқ 2 сония кўринади, кейин бир марта onFinished', (t) async {
      var finished = 0;
      await t.pumpWidget(_app(onFinished: () => finished++));
      expect(AppLaunchSplash.displayDuration, const Duration(seconds: 2));
      expect(find.byKey(AppLaunchSplash.overlayKey), findsOneWidget);
      await t.pump(const Duration(milliseconds: 1999));
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
      await t.pump(const Duration(seconds: 2));
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
      await t.pump(const Duration(seconds: 2));
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(_app(lang: 'ru'));
      expect(find.text('Здесь может быть ваша реклама'), findsOneWidget);
      expect(find.text('Разместить рекламу'), findsOneWidget);
      await t.pump(const Duration(seconds: 2));
    });

    testWidgets('кешдаги креатив: расм + «Реклама» белгиси, onShown бир марта; ҳавола босилса ёпилади', (t) async {
      final shown = <String>[];
      SplashAd? opened;
      final ad = _ad(imageUrl: 'https://firebasestorage.googleapis.com/x', linkUrl: 'https://ava.uz');
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
      await t.pump(const Duration(seconds: 2));
    });
  });

  group('SplashAd — сана ва туман', () {
    test('туман: бўш — ҳамма; рўйхат — фақат мос туман, номаълум туман — йўқ', () {
      expect(_ad().isEligible(_now, ''), isTrue);
      final g = _ad(districts: const ['gurlan']);
      expect(g.isEligible(_now, 'gurlan'), isTrue);
      expect(g.isEligible(_now, 'urganch'), isFalse);
      expect(g.isEligible(_now, ''), isFalse);
    });

    test('сана ойнаси: start ≤ now < end (чегара)', () {
      final a = _ad(start: _now, end: _now.add(const Duration(hours: 1)));
      expect(a.isInWindow(_now), isTrue);
      expect(a.isInWindow(_now.subtract(const Duration(milliseconds: 1))), isFalse);
      expect(a.isInWindow(_now.add(const Duration(hours: 1))), isFalse);
      expect(const SplashAd(id: 'x', version: 1).isInWindow(_now), isFalse);
    });

    test('pick: устуворлик, мос эмаслари ташланади', () {
      final best = SplashAd.pick([
        _ad(id: 'low', priority: 1),
        _ad(id: 'high', priority: 5, districts: const ['urganch']),
        _ad(id: 'mid', priority: 3),
        _ad(id: 'old', priority: 9, end: _now.subtract(const Duration(minutes: 1))),
      ], _now, 'gurlan');
      expect(best?.id, 'mid');
      expect(SplashAd.pick([_ad(text: const {})], _now, ''), isNull);
    });
  });

  group('SplashAdCache — фақат кеш, кунлик чегара', () {
    test('очилиш тармоқсиз: кешдаги креатив ва расм', () async {
      final store = _MemStore();
      final cache = SplashAdCache(store: store);
      expect(await cache.loadForLaunch(now: _now, districtId: 'gurlan'), isNull);
      await cache.save(_ad(imageUrl: 'https://firebasestorage.googleapis.com/x'), imageBytes: _png);
      final l = await cache.loadForLaunch(now: _now, districtId: 'gurlan');
      expect(l?.ad.id, 'ad1');
      expect(l?.imageBytes, _png);
    });

    test('расм кешда йўқ — матн бўлса матн, бўлмаса сукут', () async {
      final store = _MemStore();
      final cache = SplashAdCache(store: store);
      await cache.save(_ad(imageUrl: 'https://firebasestorage.googleapis.com/x'));
      final l = await cache.loadForLaunch(now: _now, districtId: '');
      expect(l?.imageBytes, isNull);
      expect(l?.ad.id, 'ad1');
      await cache.save(_ad(imageUrl: 'https://firebasestorage.googleapis.com/x', text: const {}));
      expect(await cache.loadForLaunch(now: _now, districtId: ''), isNull);
    });

    test('мос эмас туман/муддат — сукут', () async {
      final cache = SplashAdCache(store: _MemStore());
      await cache.save(_ad(districts: const ['gurlan']));
      expect(await cache.loadForLaunch(now: _now, districtId: 'xiva'), isNull);
      expect(await cache.loadForLaunch(now: _now.add(const Duration(days: 2)), districtId: 'gurlan'), isNull);
    });

    test('кунига 3 марта, 4-си сукут; эртасига яна', () async {
      final cache = SplashAdCache(store: _MemStore());
      await cache.save(_ad(end: _now.add(const Duration(days: 3))));
      for (var i = 0; i < SplashAdCache.maxPerDay; i++) {
        expect(await cache.loadForLaunch(now: _now, districtId: ''), isNotNull, reason: 'launch $i');
        await cache.recordImpression('ad1', _now);
      }
      expect(SplashAdCache.maxPerDay, 3);
      expect(await cache.loadForLaunch(now: _now, districtId: ''), isNull);
      final tomorrow = _now.add(const Duration(days: 1));
      expect(await cache.loadForLaunch(now: tomorrow, districtId: ''), isNotNull);
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

    test('Тошкент санаси (UTC+5)', () {
      expect(SplashAdCache.dayKey(DateTime.utc(2026, 11, 27, 19, 1)), '2026-11-28');
      expect(SplashAdCache.dayKey(DateTime.utc(2026, 11, 27, 18, 59)), '2026-11-27');
    });
  });

  group('SplashAdPrefetcher — кейинги очилиш учун, сессияда бир чақирув', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('креатив ва расм кешланади; статистика бир чақирувда юборилади', () async {
      final store = _MemStore();
      final cache = SplashAdCache(store: store);
      await cache.recordImpression('ad1', _now.subtract(const Duration(days: 1)));
      final sent = <Map<String, Map<String, int>>>[];
      var downloads = 0;
      final p = SplashAdPrefetcher(
        cache: cache,
        now: () => _now,
        fetchAds: () async => [_ad(imageUrl: 'https://firebasestorage.googleapis.com/x', districts: const ['gurlan'])],
        download: (_) async {
          downloads++;
          return _png;
        },
        sendStats: (d) async => sent.add(d),
      );
      await p.run(districtId: 'gurlan');
      expect(sent.length, 1);
      expect(await cache.pendingBefore(_now), isEmpty);
      expect((await cache.loadForLaunch(now: _now, districtId: 'gurlan'))?.imageBytes, _png);
      // 3 соат ичида қайта — тармоққа чиқмайди; расм қайта юкланмайди.
      await p.run(districtId: 'gurlan');
      expect(downloads, 1);
      expect(sent.length, 1);
    });

    test('статистика юборилмаса — йиғма сақланади; мос реклама йўқ — кеш тозаланади', () async {
      final cache = SplashAdCache(store: _MemStore());
      await cache.save(_ad());
      await cache.recordImpression('ad1', _now.subtract(const Duration(days: 1)));
      final p = SplashAdPrefetcher(
        cache: cache,
        now: () => _now,
        fetchAds: () async => [_ad(districts: const ['xiva'])],
        download: (_) async => null,
        sendStats: (_) async => throw Exception('offline'),
      );
      await p.run(districtId: 'gurlan');
      expect((await cache.pendingBefore(_now)).length, 1);
      expect(await cache.loadForLaunch(now: _now, districtId: 'gurlan'), isNull);
    });
  });

  group('«Реклама бериш» йўли', () {
    test('кирган — админ чати; кирмаган — рўйхатдан ўтиш хабари', () {
      expect(splashAdvertiseTargetFor(phone: '+998 90 123 45 67', signedIn: true), SplashAdvertiseTarget.supportChat);
      expect(splashAdvertiseTargetFor(phone: '998901234567', signedIn: false), SplashAdvertiseTarget.needLogin);
      expect(splashAdvertiseTargetFor(phone: '', signedIn: true), SplashAdvertiseTarget.needLogin);
    });

    testWidgets('чат тайёр матн билан очилади (юборилмайди)', (t) async {
      final key = GlobalKey<NavigatorState>();
      String? chat, draft;
      await t.pumpWidget(MaterialApp(navigatorKey: key, home: const Scaffold(body: Text('HOME'))));
      final f = openSplashAdvertise(
        key.currentState!,
        lang: 'uz_Cyrl',
        readPhone: () async => '998901234567',
        isSignedIn: () => true,
        chatBuilder: (id, d) {
          chat = id;
          draft = d;
          return const Scaffold(body: Text('CHAT'));
        },
      );
      await t.pumpAndSettle();
      expect(find.text('CHAT'), findsOneWidget);
      expect(chat, isNotEmpty);
      expect(draft, SplashAdTexts.chatDraft('uz_Cyrl'));
      key.currentState!.pop();
      await t.pumpAndSettle();
      await f;
    });
  });
}
