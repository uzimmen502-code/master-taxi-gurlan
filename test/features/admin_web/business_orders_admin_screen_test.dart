// «Бозор буюртмалари» админ экрани (эга 2026-11-16): серверда жорий қиймат, босқич/синовчи/туман таҳрири,
// `adminSetBusinessOrdersConfig` payload'и, тарифга ўтиш.

import 'package:ava_gurlan/core/geo/geo_context.dart';
import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/admin_web/screens/business_orders_admin_screen.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_business_orders_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _cfg = BusinessOrdersConfig(
  stage: 'internal',
  testerIds: ['998901111111', '998902222222'],
  pilotDistrictIds: ['gurlan'],
  acceptTimeoutMin: 10,
  version: 4,
  exists: true,
);

void main() {
  group('соф', () {
    test('parseTesterPhones: 9 рақам → 998…, такрорсиз, тартибли; invalidTesterPhones', () {
      final p = parseTesterPhones('901111111\n998902222222, 998902222222; 12345');
      expect(p, ['12345', '998901111111', '998902222222']);
      expect(invalidTesterPhones(p), ['12345']);
    });
    test('businessOrdersSavePayload: синовчилар фарқ, туманлар тўлиқ (такрорсиз, тартибли), босқич ва сабаб', () {
      final m = businessOrdersSavePayload(
        current: _cfg,
        stage: 'pilot',
        testerIds: ['998902222222', '998903333333'],
        pilotDistrictIds: ['urganch', 'gurlan', 'urganch'],
        reason: '  pilot boshlandi ',
      );
      expect(m, {
        'stage': 'pilot',
        'addTesterIds': ['998903333333'],
        'removeTesterIds': ['998901111111'],
        'pilotDistrictIds': ['gurlan', 'urganch'],
        'reason': 'pilot boshlandi',
      });
      final same = businessOrdersSavePayload(
        current: _cfg, stage: 'internal', testerIds: _cfg.testerIds, pilotDistrictIds: const [], reason: 'xyz',
      );
      expect(same.containsKey('addTesterIds'), isFalse);
      expect(same.containsKey('removeTesterIds'), isFalse);
      expect(same['pilotDistrictIds'], isEmpty);
    });
    test('BusinessOrdersConfig.fromMap: номаълум босқич → off', () {
      expect(BusinessOrdersConfig.fromMap({'stage': 'beta'}).stage, 'off');
      final c = BusinessOrdersConfig.fromMap({'stage': 'pilot', 'testerIds': ['1'], 'version': 3, 'exists': true});
      expect((c.stage, c.version, c.exists), ('pilot', 3, true));
      expect(c.testerIds, ['1']);
    });
  });

  group('экран', () {
    Future<void> pump(WidgetTester tester, Widget w) async {
      tester.view.physicalSize = const Size(900 * 2, 1600 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.light, home: w));
      await tester.pumpAndSettle();
    }

    testWidgets('жорий қийматлар → PILOT + туман қўшиш + синовчи → сақлаш payload; сабабсиз — юборилмайди', (tester) async {
      final sent = <Map<String, dynamic>>[];
      var loads = 0;
      await pump(
        tester,
        BusinessOrdersAdminScreen(
          loadConfig: () async {
            loads++;
            return _cfg;
          },
          saveConfig: (p) async {
            sent.add(p);
            return {'ok': true, 'version': 5, 'stage': p['stage'], 'testerCount': 3};
          },
          pickDistrict: (_) async => const GeoArea(regionId: 'xorazm', districtId: 'urganch', districtLabel: 'Урганч'),
        ),
      );
      expect(find.textContaining('Серверда: INTERNAL · v4 · синовчилар: 2 · пилот туманлар: 1'), findsOneWidget);
      expect(find.byKey(const ValueKey('bo_district_gurlan')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('bo_stage_pilot')));
      await tester.tap(find.byKey(const ValueKey('bo_add_district')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('bo_district_urganch')), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('bo_testers')), '998901111111\n998902222222\n903333333');

      await tester.tap(find.byKey(const ValueKey('bo_save')));
      await tester.pumpAndSettle();
      expect(sent, isEmpty, reason: 'сабаб мажбурий');

      await tester.enterText(find.byKey(const ValueKey('bo_reason')), 'Gurlan pilot');
      await tester.tap(find.byKey(const ValueKey('bo_save')));
      await tester.pumpAndSettle();
      expect(sent, [
        {
          'stage': 'pilot',
          'addTesterIds': ['998903333333'],
          'pilotDistrictIds': ['gurlan', 'urganch'],
          'reason': 'Gurlan pilot',
        },
      ]);
      expect(loads, 2, reason: 'сақлангач қайта ўқилади');
    });

    testWidgets('нотўғри телефон → юборилмайди; туман ўчирилади; тариф тугмаси', (tester) async {
      final sent = <Map<String, dynamic>>[];
      var tariffOpened = 0;
      await pump(
        tester,
        BusinessOrdersAdminScreen(
          loadConfig: () async => _cfg,
          saveConfig: (p) async {
            sent.add(p);
            return const {};
          },
          openTariff: (_) => tariffOpened++,
        ),
      );
      await tester.enterText(find.byKey(const ValueKey('bo_testers')), '12345');
      await tester.enterText(find.byKey(const ValueKey('bo_reason')), 'sinov');
      await tester.tap(find.byKey(const ValueKey('bo_save')));
      await tester.pumpAndSettle();
      expect(sent, isEmpty);

      final chip = find.byKey(const ValueKey('bo_district_gurlan'));
      await tester.tap(find.descendant(of: chip, matching: find.byIcon(Icons.close)));
      await tester.pumpAndSettle();
      expect(chip, findsNothing);

      await tester.tap(find.byKey(const ValueKey('bo_open_tariff')));
      expect(tariffOpened, 1);
    });

    testWidgets('юклаш хатоси → «Қайта уриниш»', (tester) async {
      var n = 0;
      await pump(
        tester,
        BusinessOrdersAdminScreen(loadConfig: () async {
          n++;
          if (n == 1) throw Exception('permission-denied');
          return _cfg;
        }),
      );
      expect(find.text('Қайта уриниш'), findsOneWidget);
      await tester.tap(find.text('Қайта уриниш'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('bo_server_line')), findsOneWidget);
    });
  });
}
