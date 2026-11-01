// Тепадаги ҳудуд устунлиги (эга, 2026-11-01): 1) GPS; 2) қўлда танлов — телефон бошқа туманга
// кўчгунча сақланади; бош экран маълумотлари кўрсатилган ҳудуд бўйича; рухсат — бир марта, ихчам.
import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/core/geo/geo_context.dart';
import 'package:ava_gurlan/core/geo/location_permission_prompt.dart';
import 'package:ava_gurlan/core/geo/module_geo_policy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

const yashnobod = GeoArea(regionId: 'toshkent_shahri', districtId: 'yashnobod', districtLabel: 'Яшнобод');
const chilonzor = GeoArea(regionId: 'toshkent_shahri', districtId: 'chilonzor', districtLabel: 'Чилонзор');
const gurlan = GeoArea(regionId: 'xorazm', districtId: 'gurlan', districtLabel: 'Гурлан');
const urganch = GeoArea(regionId: 'xorazm', districtId: 'urganch', districtLabel: 'Урганч');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GeoContext.resetForTest();
    GeoContext.homeOverride = () => yashnobod;
  });
  tearDown(GeoContext.resetForTest);

  group('applyGps', () {
    test('танлов йўқ — тепада GPS тумани (тасдиқсиз)', () async {
      expect(await GeoContext.applyGps(chilonzor), isTrue);
      expect(GeoContext.active.districtId, 'chilonzor');
      expect(GeoContext.activeSource, GeoAreaSource.location);
    });

    test('GPS йўқ (рухсат/веб/аниқланмади) — ҳеч нарса ўзгармайди', () async {
      await GeoContext.setActive(gurlan, GeoAreaSource.manual);
      expect(await GeoContext.applyGps(null), isFalse);
      expect(await GeoContext.applyGps(GeoArea.empty), isFalse);
      expect(GeoContext.active.districtId, 'gurlan');
    });

    test('GPS = яшаш жойи — тепада яшаш жойи', () async {
      await GeoContext.applyGps(chilonzor);
      await GeoContext.applyGps(yashnobod);
      expect(GeoContext.active.districtId, 'yashnobod');
      expect(GeoContext.isAway, isFalse);
    });

    test('қўлда танлов телефон ШУ туманда турганда сақланади, БОШҚА туманга кўчганда GPS қайтади', () async {
      await GeoContext.applyGps(chilonzor); // телефон Чилонзорда
      await GeoContext.setActive(gurlan, GeoAreaSource.manual); // Гурланни танлади
      expect(GeoContext.isPinned, isTrue);
      expect(await GeoContext.applyGps(chilonzor), isFalse, reason: 'жойидан жилмади — танлов қолади');
      expect(GeoContext.active.districtId, 'gurlan');

      expect(await GeoContext.applyGps(urganch), isTrue, reason: 'бошқа туманга кўчди');
      expect(GeoContext.active.districtId, 'urganch');
      expect(GeoContext.isPinned, isFalse);
    });

    test('танлов пайтида GPS номаълум эди — биринчи аниқлаш таянч, кейин кўчса GPS', () async {
      await GeoContext.setActive(gurlan, GeoAreaSource.manual);
      expect(await GeoContext.applyGps(chilonzor), isFalse);
      expect(GeoContext.active.districtId, 'gurlan');
      expect(await GeoContext.applyGps(chilonzor), isFalse);
      expect(await GeoContext.applyGps(yashnobod), isTrue);
      expect(GeoContext.active.districtId, 'yashnobod');
    });

    test('ойнадан «Яшаш жойим» ҳам қўлда танлов — GPS кўчгунча устидан ёзмайди', () async {
      await GeoContext.applyGps(chilonzor);
      await GeoContext.chooseHome();
      expect(GeoContext.active.districtId, 'yashnobod');
      expect(await GeoContext.applyGps(chilonzor), isFalse);
      expect(GeoContext.active.districtId, 'yashnobod');
      expect(await GeoContext.applyGps(gurlan), isTrue);
      expect(GeoContext.active.districtId, 'gurlan');
    });

    test('«Ҳозирги жойим» (location) — белги ечилади, GPS эргашади', () async {
      await GeoContext.setActive(gurlan, GeoAreaSource.manual);
      await GeoContext.setActive(chilonzor, GeoAreaSource.location);
      expect(GeoContext.isPinned, isFalse);
      expect(await GeoContext.applyGps(urganch), isTrue);
    });

    test('танлов белгиси илова қайта очилганда сақланади', () async {
      await GeoContext.applyGps(chilonzor);
      await GeoContext.setActive(gurlan, GeoAreaSource.manual);
      GeoContext.resetForTest(); // «илова ёпилди» — хотира тозаланади, prefs қолади
      GeoContext.homeOverride = () => yashnobod;
      await GeoContext.load();
      expect(GeoContext.active.districtId, 'gurlan');
      expect(GeoContext.isPinned, isTrue);
      expect(await GeoContext.applyGps(chilonzor), isFalse);
      expect(await GeoContext.applyGps(urganch), isTrue);
    });

    test('эски илова: қўлда танланган (белгисиз) — сақланади, таянч биринчи GPS', () async {
      SharedPreferences.setMockInitialValues({
        'geo_active_v1': '{"area":{"regionId":"xorazm","districtId":"gurlan","regionLabel":"","districtLabel":"Гурлан"},"source":"manual"}',
      });
      await GeoContext.load();
      expect(GeoContext.isPinned, isTrue);
      expect(await GeoContext.applyGps(chilonzor), isFalse);
      expect(GeoContext.active.districtId, 'gurlan');
    });
  });

  group('homeScopeFor — бош экран кўрсатилган ҳудуд бўйича', () {
    test('модул ичидаги бошқа ҳудуд/даража бош экранга таъсир қилмайди', () async {
      await GeoContext.applyGps(chilonzor);
      await GeoContext.setScope(
        'cheap_products_home',
        const GeoScope(level: GeoLevel.nation, area: gurlan, pinned: true),
      );
      expect(GeoContext.scopeFor('cheap_products_home').level, GeoLevel.nation);
      final home = GeoContext.homeScopeFor('cheap_products_home');
      expect(home.level, GeoLevel.district);
      expect(home.area.districtId, 'chilonzor');
    });
  });

  group('askLocationPermissionOnce', () {
    Future<bool> run(WidgetTester tester, {required LocationPermission current, String? tap, LocationPermission grant = LocationPermission.whileInUse}) async {
      late Future<bool> result;
      var requests = 0;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          return Scaffold(
            body: TextButton(
              onPressed: () => result = askLocationPermissionOnce(ctx,
                  check: () async => current, request: () async {
                    requests++;
                    return grant;
                  }),
              child: const Text('go'),
            ),
          );
        }),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      if (tap != null) {
        expect(find.byKey(const ValueKey('geo_perm_dialog')), findsOneWidget);
        await tester.tap(find.byKey(ValueKey(tap)));
        await tester.pumpAndSettle();
      }
      final r = await result;
      if (tap != 'geo_perm_allow') expect(requests, 0);
      return r;
    }

    testWidgets('«Рухсат бериш» — тизим сўрови, рухсат берилди', (tester) async {
      expect(await run(tester, current: LocationPermission.denied, tap: 'geo_perm_allow'), isTrue);
    });

    testWidgets('«Кейин» — сўров йўқ ва КЕЙИН ҚАЙТА СЎРАЛМАЙДИ', (tester) async {
      expect(await run(tester, current: LocationPermission.denied, tap: 'geo_perm_later'), isFalse);
      expect(await run(tester, current: LocationPermission.denied), isFalse);
      expect(find.byKey(const ValueKey('geo_perm_dialog')), findsNothing);
    });

    testWidgets('рухсат аллақачон бор ёки абадий рад — ойна чиқмайди', (tester) async {
      expect(await run(tester, current: LocationPermission.whileInUse), isFalse);
      SharedPreferences.setMockInitialValues({});
      expect(await run(tester, current: LocationPermission.deniedForever), isFalse);
      expect(find.byKey(const ValueKey('geo_perm_dialog')), findsNothing);
    });

    test('ихчам матнлар уч тилда мавжуд (ортиқча сўзсиз: матн ≤ 40 белги)', () {
      for (final lang in ['uz_Cyrl', 'uz_Latn', 'ru']) {
        final m = jsonDecode(File('assets/lang/$lang.json').readAsStringSync()) as Map<String, dynamic>;
        for (final k in ['geo_perm_title', 'geo_perm_body', 'geo_perm_allow', 'geo_perm_later']) {
          final v = m[k];
          expect(v, isA<String>(), reason: '$lang:$k');
          expect((v as String).length, lessThanOrEqualTo(40), reason: '$lang:$k');
        }
      }
    });
  });
}
