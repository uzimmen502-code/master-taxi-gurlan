import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/features/my_shop/pending_shop_link.dart';
import 'package:ava_gurlan/features/tv_market/screens/tv_shop_public_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Android App Links (2026-10-25): `https://master-taxi-gurlan.web.app/s/<publicId>` иловани очади
/// ва веб `/?shop=<id>` билан бир хил навбатга (PendingShopLink) тушади.
const _base = 'https://master-taxi-gurlan.web.app';

/// Ҳар тестдан кейин навбат тоза бўлсин (статик ҳолат).
void _drain() {
  PendingShopLink.take();
}

/// HomeScreen'даги уланиш билан бир хил: [PendingShopLink.arrivals] → [PendingShopLink.openIfAny].
class _HomeLike extends StatefulWidget {
  const _HomeLike({required this.resolve, required this.push, required this.openRestaurant});

  final Future<({String ownerPhone, String businessId, String restaurantId})?> Function(String) resolve;
  final void Function(Widget) push;
  final Future<void> Function(BuildContext, String, String) openRestaurant;

  @override
  State<_HomeLike> createState() => _HomeLikeState();
}

class _HomeLikeState extends State<_HomeLike> {
  @override
  void initState() {
    super.initState();
    PendingShopLink.arrivals.addListener(_onArrived);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_open());
    });
  }

  Future<void> _open() => PendingShopLink.openIfAny(context,
      resolve: widget.resolve, push: widget.push, openRestaurant: widget.openRestaurant);

  void _onArrived() {
    if (mounted) unawaited(_open());
  }

  @override
  void dispose() {
    PendingShopLink.arrivals.removeListener(_onArrived);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

void main() {
  tearDown(_drain);

  group('parseAppLink', () {
    test('тўғри ID; манба qr / link / номаълум → link', () {
      expect(PendingShopLink.parseAppLink(Uri.parse('$_base/s/AbCdEfGh23')), (id: 'AbCdEfGh23', source: 'link'));
      expect(PendingShopLink.parseAppLink(Uri.parse('$_base/s/AbCdEfGh23?src=qr')), (id: 'AbCdEfGh23', source: 'qr'));
      expect(PendingShopLink.parseAppLink(Uri.parse('$_base/s/AbCdEfGh23?src=link')), (id: 'AbCdEfGh23', source: 'link'));
      expect(PendingShopLink.parseAppLink(Uri.parse('$_base/s/AbCdEfGh23?src=QR')), (id: 'AbCdEfGh23', source: 'link'));
      expect(PendingShopLink.parseAppLink(Uri.parse('$_base/s/AbCdEfGh23?src=evil&x=1')), (id: 'AbCdEfGh23', source: 'link'));
      expect(PendingShopLink.parseAppLink(Uri.parse('$_base/s/AbCdEfGh23/')), (id: 'AbCdEfGh23', source: 'link'),
          reason: 'охиридаги / (сервер ҳам шундай қабул қилади)');
    });

    test('/s/ ҳаволаси, лекин ID нотўғри ёки ортиқча йўл — id null («мавжуд эмас»)', () {
      for (final bad in [
        '$_base/s/',
        '$_base/s/AbCdEfGh2', // 9 белги
        '$_base/s/AbCdEfGh234', // 11 белги
        '$_base/s/998901111111',
        '$_base/s/AbCdEfGh2%21',
        '$_base/s/AbCdEfGh23/extra',
        '$_base/s/x/AbCdEfGh23',
      ]) {
        expect(PendingShopLink.parseAppLink(Uri.parse(bad))?.id, isNull, reason: bad);
        expect(PendingShopLink.parseAppLink(Uri.parse(bad)), isNotNull, reason: bad);
      }
    });

    test('/s/ эмас, бошқа хост ёки http — эътиборсиз (null)', () {
      for (final other in [
        '$_base/',
        '$_base/?shop=AbCdEfGh23',
        '$_base/clip/AbCdEfGh23',
        '$_base/shop/AbCdEfGh23',
        '$_base/admin/s/AbCdEfGh23',
        '$_base/downloads/',
        'https://evil.example/s/AbCdEfGh23',
        'https://master-taxi-gurlan.firebaseapp.com/s/AbCdEfGh23',
        'http://master-taxi-gurlan.web.app/s/AbCdEfGh23',
        'avazona://s/AbCdEfGh23',
      ]) {
        expect(PendingShopLink.parseAppLink(Uri.parse(other)), isNull, reason: other);
      }
    });

    test('хост ҳарф катталигига қарамайди (Uri хостни кичик қилади)', () {
      expect(PendingShopLink.parseAppLink(Uri.parse('https://Master-Taxi-Gurlan.WEB.app/s/AbCdEfGh23'))?.id, 'AbCdEfGh23');
    });
  });

  group('captureAppLink / listenAppLinks', () {
    test('ушланади, манба сақланади, arrivals ошади; бир марта олинади', () {
      final before = PendingShopLink.arrivals.value;
      expect(PendingShopLink.captureAppLink(Uri.parse('$_base/s/AbCdEfGh23?src=qr')), isTrue);
      expect(PendingShopLink.arrivals.value, before + 1);
      expect(PendingShopLink.source, 'qr');
      expect(PendingShopLink.take(), 'AbCdEfGh23');
      expect(PendingShopLink.take(), isNull);
    });

    test('бизники эмас — навбат ва arrivals ўзгармайди', () {
      PendingShopLink.captureAppLink(Uri.parse('$_base/s/AbCdEfGh23'));
      final before = PendingShopLink.arrivals.value;
      expect(PendingShopLink.captureAppLink(Uri.parse('https://evil.example/s/ZZZZZZZZZZ')), isFalse);
      expect(PendingShopLink.arrivals.value, before);
      expect(PendingShopLink.take(), 'AbCdEfGh23', reason: 'аввалги ҳавола бузилмади');
    });

    test('оқим: бошланғич (cold) ва кейинги (warm) ҳаволалар; оқим хатоси илованинг йиқитмайди', () async {
      final links = StreamController<Uri>();
      final sub = PendingShopLink.listenAppLinks(links.stream);
      addTearDown(sub.cancel);
      links.add(Uri.parse('$_base/s/AbCdEfGh23?src=qr'));
      await Future<void>.delayed(Duration.zero);
      expect([PendingShopLink.take(), PendingShopLink.source], ['AbCdEfGh23', 'qr']);
      links.addError(StateError('channel'));
      links.add(Uri.parse('$_base/s/ZyXwVuTs98'));
      await Future<void>.delayed(Duration.zero);
      expect([PendingShopLink.take(), PendingShopLink.source], ['ZyXwVuTs98', 'link']);
      await links.close();
    });
  });

  group('App Link → PendingShopLink → очиш', () {
    late List<String> resolved;
    late List<String> restaurants;
    late List<Widget> pushed;
    late Map<String, ({String ownerPhone, String businessId, String restaurantId})?> targets;

    Future<void> pumpHome(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: _HomeLike(
          resolve: (id) async {
            resolved.add(id);
            return targets[id];
          },
          push: pushed.add,
          openRestaurant: (c, rid, src) async => restaurants.add('$rid|$src'),
        ),
      ));
      await tester.pump();
    }

    setUp(() {
      resolved = [];
      restaurants = [];
      pushed = [];
      targets = {
        'AbCdEfGh23': (ownerPhone: '998901111111', businessId: 'm1', restaurantId: ''),
        'RrEeSsTt01': (ownerPhone: '', businessId: '', restaurantId: 'r1'),
      };
    });

    testWidgets('cold start: ҳавола бош саҳифадан олдин келди — очилгач дўкон (йўналиш билан), манба qr', (tester) async {
      PendingShopLink.captureAppLink(Uri.parse('$_base/s/AbCdEfGh23?src=qr'));
      await pumpHome(tester);
      expect(resolved, ['AbCdEfGh23']);
      expect(pushed.single, isA<TvShopPublicScreen>());
      final s = pushed.single as TvShopPublicScreen;
      expect([s.ownerPhone, s.businessId, s.source], ['998901111111', 'm1', 'qr']);
      expect(restaurants, isEmpty);
    });

    testWidgets('warm: илова очиқ — ресторан ҳаволаси ресторан очувчига кетади; дўкон экрани йўқ', (tester) async {
      await pumpHome(tester);
      expect(resolved, isEmpty);
      PendingShopLink.captureAppLink(Uri.parse('$_base/s/RrEeSsTt01'));
      await tester.pump();
      expect(restaurants, ['r1|link']);
      expect(pushed, isEmpty);
    });

    testWidgets('warm: мавжуд эмас / нотўғри ID — «вақтинча мавжуд эмас», ҳеч нарса очилмайди', (tester) async {
      await pumpHome(tester);
      PendingShopLink.captureAppLink(Uri.parse('$_base/s/ZZZZZZZZZZ'));
      await tester.pump();
      await tester.pump();
      expect(resolved, ['ZZZZZZZZZZ']);
      expect(find.text('shop_unavailable'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(Scaffold))).removeCurrentSnackBar();
      await tester.pumpAndSettle();

      PendingShopLink.captureAppLink(Uri.parse('$_base/s/bad'));
      await tester.pump();
      expect(resolved, ['ZZZZZZZZZZ'], reason: 'нотўғри ID серверга юборилмайди');
      expect(find.text('shop_unavailable'), findsOneWidget);
      expect([pushed, restaurants], [isEmpty, isEmpty]);
    });

    testWidgets('бир ҳавола икки марта очилмайди (post-frame + listener бир вақтда)', (tester) async {
      await pumpHome(tester);
      PendingShopLink.captureAppLink(Uri.parse('$_base/s/AbCdEfGh23'));
      // Иккинчи чақирув (масалан, бошқа экран ҳам тингласа) — навбат бўш.
      await PendingShopLink.openIfAny(tester.element(find.byType(Scaffold)),
          resolve: (id) async => fail('иккинчи марта ечилмаслиги керак'));
      await tester.pump();
      expect(pushed.length, 1);
      expect(resolved, ['AbCdEfGh23']);
    });
  });

  group('Digital Asset Links ва manifest', () {
    final fp = RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$');

    test('web/.well-known/assetlinks.json: тузилма, пакет, SHA-256 формати', () {
      final file = File('web/.well-known/assetlinks.json');
      expect(file.existsSync(), isTrue);
      final json = jsonDecode(file.readAsStringSync());
      expect(json, isA<List<dynamic>>());
      final list = json as List<dynamic>;
      expect(list, hasLength(1));
      final st = list.single as Map<String, dynamic>;
      expect(st['relation'], ['delegate_permission/common.handle_all_urls']);
      final target = st['target'] as Map<String, dynamic>;
      expect(target['namespace'], 'android_app');
      expect(target['package_name'], 'uz.ava.gurlan');
      final fps = (target['sha256_cert_fingerprints'] as List<dynamic>).cast<String>();
      for (final f in fps) {
        expect(fp.hasMatch(f), isTrue, reason: f);
      }
      expect(fps.toSet().length, fps.length, reason: 'такрор йўқ');
      // Айнан шу иккита (JSON'да изоҳ бўлмайди — манба шу ерда):
      //  1) 3E:4B:… — релиз/upload калити (CONFIRMED, лойиҳа раҳбари);
      //  2) 00:AB:… — Firebase'да androidApp uz.ava.gurlan учун рўйхатдаги калит, Play App Signing калити деб
      //     INFERRED (2026-10-25, раҳбар фақат ўқиб текширган). Учинчи рўйхатдаги 88:58:53:… — маҳаллий debug
      //     калити, ҚЎШИЛМАЙДИ (debug APK production ҳаволаларини тутиб олмасин).
      expect(fps, [
        '3E:4B:07:6D:DF:98:47:86:F0:83:D0:E2:7D:BF:08:B8:4C:3F:02:5E:CB:8B:C9:4E:76:FA:44:30:EC:34:E9:38',
        '00:AB:F3:80:BE:74:13:95:B9:2D:E3:79:7E:05:50:4D:63:D2:83:6D:5A:73:97:C4:B3:EB:C7:68:3D:C3:0A:5F',
      ]);
      expect(fps.any((f) => f.startsWith('88:58:53:')), isFalse, reason: 'debug калити йўқ');
    });

    test('пакет номи Gradle applicationId билан бир хил', () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(gradle, contains('applicationId = "uz.ava.gurlan"'));
    });

    test('manifest: autoVerify intent-filter хост/йўл PendingShopLink билан бир хил; Flutter deep linking ўчиқ', () {
      final m = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      final filter = RegExp(r'<intent-filter android:autoVerify="true">([\s\S]*?)</intent-filter>').firstMatch(m);
      expect(filter, isNotNull);
      final body = filter!.group(1)!;
      for (final s in [
        'android.intent.action.VIEW',
        'android.intent.category.DEFAULT',
        'android.intent.category.BROWSABLE',
        'android:scheme="https"',
        'android:host="${PendingShopLink.appLinkHost}"',
        'android:pathPrefix="/s/"',
      ]) {
        expect(body, contains(s), reason: s);
      }
      expect(body, isNot(contains('android:scheme="http"')));
      expect(
          RegExp(r'android:name="flutter_deeplinking_enabled"\s+android:value="false"').hasMatch(m), isTrue);
    });
  });
}
