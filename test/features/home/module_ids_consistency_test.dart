import 'package:ava_gurlan/features/home/home_services_catalog.dart';
import 'package:ava_gurlan/features/home/widgets/ava_business_sheet.dart';
import 'package:ava_gurlan/features/home/widgets/service_spotlight_item.dart';
import 'package:ava_gurlan/models/service_module_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Модул ID'лари бир манбада: `kKnownModuleIds`. Каталогда ёки «＋»да рўйхатда
/// йўқ ID бўлса — `ServiceConfigHolder.statusOf` уни ЯШИРИН деб ҳисоблайди
/// ва админ «Ҳудудлар ва хизматлар»да ҳам кўринмайди.
void main() {
  test('kKnownModuleIds — такрорсиз; 6 бозор модули бор', () {
    expect(kKnownModuleIds.toSet().length, kKnownModuleIds.length);
    expect(
      kKnownModuleIds,
      containsAll(['livestock_market', 'auto_market', 'meat_market', 'farm_market', 'electronics_market', 'appliances_market']),
    );
  });

  test('kAvaCreateModules қийматлари ⊆ kKnownModuleIds', () {
    final unknown = [
      for (final ids in kAvaCreateModules.values)
        for (final id in ids)
          if (!kKnownModuleIds.contains(id)) id,
    ];
    expect(unknown, isEmpty);
  });

  testWidgets('buildHomeServices дарвозалари ⊆ kKnownModuleIds; бозорлар плиткаси йўқ',
      (tester) async {
    late List<ServiceSpotlightItem> items;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        items = buildHomeServices(
          context,
          a: HomeServiceActions(
            push: (_) async {},
            openModule: (_) async {},
            openYukModule: (_, __) async {},
            openPayment: (_) async {},
            openDating: () async {},
            showComingSoon: () {},
          ),
        );
        return const SizedBox();
      }),
    ));
    expect(items, isNotEmpty);
    final unknownGates = [
      for (final e in items)
        if (!kKnownModuleIds.contains(e.gate)) e.gate,
    ];
    expect(unknownGates, isEmpty);
    // gateId'сиз плиткаларда moduleId = дарвоза.
    for (final e in items.where((e) => e.gateId == null)) {
      expect(kKnownModuleIds, contains(e.moduleId));
    }
    // Эга, 2026-11-15: бозор модуллари учун бош саҳифа плиткаси ҲОЗИРЧА ЙЎҚ.
    final ids = items.map((e) => e.moduleId).toSet();
    for (final m in ['livestock_market', 'auto_market', 'meat_market', 'farm_market', 'electronics_market', 'appliances_market']) {
      expect(ids.contains(m), isFalse, reason: m);
    }
  });
}
