import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/core/service_config_holder.dart';
import 'package:ava_gurlan/features/demand_offer/domain/demand_enums.dart';
import 'package:ava_gurlan/features/demand_offer/presentation/activity/demand_activity_entry.dart'
    show kDemandUiAdapters;
import 'package:ava_gurlan/features/demand_offer/ui_adapters/demand_ui_adapter.dart';
import 'package:ava_gurlan/features/home/home_intent_router.dart';
import 'package:ava_gurlan/models/service_module_config.dart';
import 'package:ava_gurlan/models/user_address.dart';
import 'package:flutter_test/flutter_test.dart';

/// Аудит №4: қидирувдаги intent карточкаси → қаерга олиб боради.
void main() {
  tearDown(ServiceConfigHolder.resetForTest);

  group('intentTargetFor', () {
    test('ядрога уланган модул (service) — сўров формаси', () {
      const i = IntentResult(
        rawText: 'сантехник керак',
        module: DemandModule.service,
        categoryId: 'santexnik',
        coreReady: true,
      );
      expect(intentTargetFor(i), IntentTarget.composer);
    });

    test('ядрога уланмаган модуллар — иловадаги мавжуд экран', () {
      IntentResult x(DemandModule m, String screen) =>
          IntentResult(rawText: 'x', module: m, existingScreen: screen);
      expect(intentTargetFor(x(DemandModule.courier, 'courier')), IntentTarget.courier);
      expect(intentTargetFor(x(DemandModule.intercityTaxi, 'intercity_taxi')),
          IntentTarget.intercityTaxi);
      expect(intentTargetFor(x(DemandModule.realty, 'realty')), IntentTarget.realty);
      expect(intentTargetFor(x(DemandModule.market, 'market')), IntentTarget.market);
      expect(intentTargetFor(x(DemandModule.freightLocal, 'yuk_local')),
          IntentTarget.freightLocal);
    });

    test('номаълум экран / модулсиз — ҳеч нарса очилмайди (йиқилмайди)', () {
      expect(intentTargetFor(const IntentResult(rawText: 'салом')), IntentTarget.none);
      expect(
        intentTargetFor(const IntentResult(
            rawText: 'x', module: DemandModule.food, existingScreen: 'kelajak')),
        IntentTarget.none,
      );
    });

    test('REGRESSION: луғатдаги ҳар existingScreen қиймати мақсадга эга', () {
      // Луғатга янги `existingScreen` қўшилиб, бу ерда унутилса — карточка
      // босилганда ҳеч нарса бўлмай қолади. Шу тест уни ушлайди.
      final json = jsonDecode(File('assets/data/intent_keywords.json')
          .readAsStringSync()) as Map<String, dynamic>;
      final modules = json['modules'] as Map<String, dynamic>;
      for (final e in modules.entries) {
        final m = e.value as Map<String, dynamic>;
        final screen = (m['existingScreen'] ?? '').toString();
        if (screen.isEmpty) continue;
        final target = intentTargetFor(
            IntentResult(rawText: 'x', existingScreen: screen, module: DemandModule.courier));
        expect(target, isNot(IntentTarget.none), reason: '${e.key} → $screen');
      }
    });

    test('ядрога уланган модулнинг UI adapter\'и бор (форма очилади)', () {
      expect(kDemandUiAdapters[DemandModule.service], isNotNull);
    });
  });

  group('demandPointFromAddress', () {
    test('GPS бор — координата ва манзил матни; регион/туман ЮБОРИЛМАЙДИ', () {
      const a = UserAddress(
        mfy: 'Бирлашган',
        street: 'Навоий',
        house: '12',
        lat: 41.84,
        lng: 60.39,
      );
      final p = demandPointFromAddress(a)!;
      expect(p.lat, 41.84);
      expect(p.lng, 60.39);
      expect(p.hasCoords, isTrue);
      expect(p.addressText, contains('Навоий'));
      expect(p.regionId, isEmpty);
      expect(p.districtId, isEmpty);
      expect(p.geohash, isEmpty);
    });

    test('координата йўқ / (0,0) / манзил йўқ — null', () {
      expect(demandPointFromAddress(null), isNull);
      expect(demandPointFromAddress(const UserAddress(mfy: 'A', street: 'B', house: '1')),
          isNull);
      expect(demandPointFromAddress(const UserAddress(lat: 0, lng: 0)), isNull);
      expect(demandPointFromAddress(const UserAddress(lat: 41.8)), isNull);
    });
  });

  group('«demand_intent» дарвозаси', () {
    test('маълум модул, лекин конфигда йўқ — ЁПИҚ (OFF)', () {
      expect(kKnownModuleIds, contains('demand_intent'));
      ServiceConfigHolder.setForTest();
      expect(ServiceConfigHolder.isOpenable('demand_intent'), isFalse);
      expect(ServiceConfigHolder.isVisible('demand_intent'), isFalse);
    });
  });
}
