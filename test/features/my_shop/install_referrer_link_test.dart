import 'dart:async';

import 'package:ava_gurlan/features/my_shop/install_referrer_link.dart';
import 'package:ava_gurlan/features/my_shop/pending_shop_link.dart';
import 'package:ava_gurlan/features/tv_market/screens/tv_shop_public_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Deferred deep link (2026-10-25): Play Install Referrer → PendingShopLink (ўша навбат).
const _base = 'https://master-taxi-gurlan.web.app';

Future<SharedPreferences> _prefs([Map<String, Object> init = const {}]) async {
  SharedPreferences.setMockInitialValues(init);
  return SharedPreferences.getInstance();
}

void main() {
  setUp(PendingShopLink.resetForTest);
  tearDown(PendingShopLink.resetForTest);

  group('parseInstallReferrer', () {
    test('тўғри: ava_shop + src (qr / link / номаълум → link); тўлиқ кодланган ҳам', () {
      expect(PendingShopLink.parseInstallReferrer('ava_shop=AbCdEfGh23&src=qr'), (id: 'AbCdEfGh23', source: 'qr'));
      expect(PendingShopLink.parseInstallReferrer('ava_shop=AbCdEfGh23&src=link'), (id: 'AbCdEfGh23', source: 'link'));
      expect(PendingShopLink.parseInstallReferrer('ava_shop=AbCdEfGh23'), (id: 'AbCdEfGh23', source: 'link'));
      expect(PendingShopLink.parseInstallReferrer('ava_shop=AbCdEfGh23&src=QR'), (id: 'AbCdEfGh23', source: 'link'));
      expect(PendingShopLink.parseInstallReferrer('src=qr&ava_shop=AbCdEfGh23&utm_source=x'), (id: 'AbCdEfGh23', source: 'qr'));
      expect(PendingShopLink.parseInstallReferrer('ava_shop%3DAbCdEfGh23%26src%3Dqr'), (id: 'AbCdEfGh23', source: 'qr'),
          reason: 'Play декод қилмаган ҳолат');
      expect(PendingShopLink.parseInstallReferrer('  ava_shop=AbCdEfGh23&src=qr '), (id: 'AbCdEfGh23', source: 'qr'));
    });

    test('органик / бўш / ахлат / нотўғри ID — null', () {
      for (final r in <String?>[
        null,
        '',
        'utm_source=google-play&utm_medium=organic',
        'utm_source=(not%20set)&utm_medium=(not%20set)',
        'ava_shop=',
        'ava_shop=AbCdEfGh2',
        'ava_shop=AbCdEfGh234',
        'ava_shop=998901111111',
        'ava_shop=../../x',
        'ava_shop=AbCdEfGh2%21',
        'shop=AbCdEfGh23',
        '%E0%A4%A',
        '%%%',
        'ava_shop=${'A' * 600}',
        'https://evil.example/s/AbCdEfGh23',
      ]) {
        expect(PendingShopLink.parseInstallReferrer(r), isNull, reason: '$r');
      }
    });
  });

  group('captureInstallReferrer — App Link устун, икки марта очилмайди', () {
    test('навбатга тушади, arrivals ошади, манба сақланади', () {
      final before = PendingShopLink.arrivals.value;
      expect(PendingShopLink.captureInstallReferrer('ava_shop=AbCdEfGh23&src=qr'), isTrue);
      expect(PendingShopLink.arrivals.value, before + 1);
      expect(PendingShopLink.source, 'qr');
      expect(PendingShopLink.take(), 'AbCdEfGh23');
    });

    test('App Link аввал келган — referrer эътиборсиз (навбатдаги ҳавола бузилмайди)', () {
      PendingShopLink.captureAppLink(Uri.parse('$_base/s/ZyXwVuTs98'));
      final before = PendingShopLink.arrivals.value;
      expect(PendingShopLink.captureInstallReferrer('ava_shop=AbCdEfGh23&src=qr'), isFalse);
      expect(PendingShopLink.arrivals.value, before);
      expect([PendingShopLink.take(), PendingShopLink.source], ['ZyXwVuTs98', 'link']);
    });

    test('App Link очилгандан кейин ҳам (навбат бўш) referrer эътиборсиз', () {
      PendingShopLink.captureAppLink(Uri.parse('$_base/s/ZyXwVuTs98'));
      PendingShopLink.take();
      expect(PendingShopLink.captureInstallReferrer('ava_shop=AbCdEfGh23'), isFalse);
      expect(PendingShopLink.take(), isNull);
    });

    test('referrer кейин бошқа App Link — App Link ютади (навбатда у)', () {
      PendingShopLink.captureInstallReferrer('ava_shop=AbCdEfGh23&src=qr');
      PendingShopLink.captureAppLink(Uri.parse('$_base/s/ZyXwVuTs98'));
      expect([PendingShopLink.take(), PendingShopLink.source], ['ZyXwVuTs98', 'link']);
    });

    test('referrer дўконни очди, кейин ЎША App Link келди — иккинчи марта навбатга тушмайди; кейинги босиш — очилади', () {
      PendingShopLink.captureInstallReferrer('ava_shop=AbCdEfGh23&src=qr');
      expect(PendingShopLink.take(), 'AbCdEfGh23');
      final before = PendingShopLink.arrivals.value;
      expect(PendingShopLink.captureAppLink(Uri.parse('$_base/s/AbCdEfGh23?src=qr')), isTrue);
      expect(PendingShopLink.arrivals.value, before, reason: 'дубликат — arrivals ўзгармайди');
      expect(PendingShopLink.take(), isNull);
      // Фойдаланувчи кейин атайлаб яна босса — одатдагидек.
      PendingShopLink.captureAppLink(Uri.parse('$_base/s/AbCdEfGh23'));
      expect(PendingShopLink.take(), 'AbCdEfGh23');
    });
  });

  group('InstallReferrerLink.checkOnce', () {
    test('янги ўрнатиш: бир марта ўқилади ва навбатга тушади; иккинчи ишга тушишда Play сўралмайди', () async {
      final prefs = await _prefs();
      var reads = 0;
      Future<String?> read() async {
        reads++;
        return 'ava_shop=AbCdEfGh23&src=qr';
      }

      await InstallReferrerLink.checkOnce(prefs: prefs, freshInstall: true, read: read);
      expect(reads, 1);
      expect(prefs.getBool(InstallReferrerLink.prefsKey), isTrue);
      expect([PendingShopLink.take(), PendingShopLink.source], ['AbCdEfGh23', 'qr']);

      await InstallReferrerLink.checkOnce(prefs: prefs, freshInstall: true, read: read);
      expect(reads, 1, reason: 'бир марта');
      expect(PendingShopLink.take(), isNull);
    });

    test('эски фойдаланувчи (янгиланиш): Play сўралмайди, белги қўйилади', () async {
      final prefs = await _prefs({'saved_language': 'uz_Cyrl'});
      var reads = 0;
      await InstallReferrerLink.checkOnce(prefs: prefs, freshInstall: false, read: () async {
        reads++;
        return 'ava_shop=AbCdEfGh23';
      });
      expect(reads, 0);
      expect(prefs.getBool(InstallReferrerLink.prefsKey), isTrue);
      expect(PendingShopLink.take(), isNull);
    });

    test('органик referrer — ҳеч нарса очилмайди, белги қўйилади', () async {
      final prefs = await _prefs();
      await InstallReferrerLink.checkOnce(
          prefs: prefs, freshInstall: true, read: () async => 'utm_source=google-play&utm_medium=organic');
      expect(PendingShopLink.take(), isNull);
      expect(prefs.getBool(InstallReferrerLink.prefsKey), isTrue);
    });

    test('хато (хизмат йўқ) ва null — жим; қайта уринилмайди', () async {
      for (final read in <Future<String?> Function()>[
        () async => throw PlatformException(code: 'SERVICE_UNAVAILABLE'),
        () async => null,
      ]) {
        final prefs = await _prefs();
        await expectLater(InstallReferrerLink.checkOnce(prefs: prefs, freshInstall: true, read: read), completes);
        expect(PendingShopLink.take(), isNull);
        expect(prefs.getBool(InstallReferrerLink.prefsKey), isTrue);
      }
    });

    test('timeout — жим тугайди, кечиккан жавоб навбатга тушмайди', () async {
      final prefs = await _prefs();
      final slow = Completer<String?>();
      await expectLater(
        InstallReferrerLink.checkOnce(
            prefs: prefs, freshInstall: true, read: () => slow.future, timeout: const Duration(milliseconds: 20)),
        completes,
      );
      slow.complete('ava_shop=AbCdEfGh23');
      await Future<void>.delayed(Duration.zero);
      expect(PendingShopLink.take(), isNull);
      expect(prefs.getBool(InstallReferrerLink.prefsKey), isTrue);
    });
  });

  testWidgets('referrer бош саҳифа очиқ турганда келди — arrivals орқали дўкон очилади (манба qr)', (tester) async {
    final pushed = <Widget>[];
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      void onArrived() => unawaited(PendingShopLink.openIfAny(context,
          resolve: (id) async => (ownerPhone: '998901111111', businessId: '', restaurantId: ''), push: pushed.add));
      PendingShopLink.arrivals.addListener(onArrived);
      addTearDown(() => PendingShopLink.arrivals.removeListener(onArrived));
      return const Scaffold(body: SizedBox());
    })));
    final prefs = await _prefs();
    await tester.runAsync(() => InstallReferrerLink.checkOnce(
        prefs: prefs, freshInstall: true, read: () async => 'ava_shop=AbCdEfGh23&src=qr'));
    await tester.pump();
    await tester.pump();
    expect(pushed.single, isA<TvShopPublicScreen>());
    expect((pushed.single as TvShopPublicScreen).source, 'qr');
  });
}
