// «Курьер хизмати» (эга, 2026-10-19): босилганда курьер уланган БАРЧА хизматлар
// кўрсатилади — аввал фақат Нон ва Гилам эди (қўлда ёзилган).

import 'package:ava_gurlan/core/service_config_holder.dart';
import 'package:ava_gurlan/features/home/home_services_catalog.dart';
import 'package:ava_gurlan/features/home/screens/courier_services_hub_screen.dart';
import 'package:ava_gurlan/features/home/widgets/service_spotlight_item.dart';
import 'package:ava_gurlan/models/service_module_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

HomeServiceActions _actions() => HomeServiceActions(
      push: (_) async {},
      openModule: (_) async {},
      openYukModule: (_, __) async {},
      openPayment: (_) async {},
      openDating: () async {},
      showComingSoon: () {},
    );

void main() {
  tearDown(ServiceConfigHolder.resetForTest);

  Future<List<String>> idsFor(
      WidgetTester t, Map<String, ModuleStatus> cfg) async {
    ServiceConfigHolder.setForTest(
        defaults: ServiceModuleConfig(cfg), enforce: true);
    late List<ServiceSpotlightItem> items;
    await t.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        items = courierConnectedServices(context, a: _actions());
        return const SizedBox();
      }),
    ));
    return items.map((e) => e.moduleId).toList();
  }

  testWidgets(
      'каталог: курьер уланган хизматлар — Нон, Кафе-Ресторан, Гилам, Сут (шу тартибда)',
      (t) async {
    final all = {
      for (final id in kCourierConnectedModuleIds) id: ModuleStatus.enabled
    };
    expect(
        await idsFor(t, all), ['bread', 'restaurants', 'carpet_wash', 'milk']);
  });

  testWidgets('бош саҳифада ёпиқ (hidden) хизмат курьер рўйхатида ҳам чиқмайди',
      (t) async {
    final cfg = {
      'bread': ModuleStatus.enabled,
      'restaurants': ModuleStatus.hidden,
      'carpet_wash': ModuleStatus.enabled,
      'milk': ModuleStatus.hidden,
    };
    expect(await idsFor(t, cfg), ['bread', 'carpet_wash']);
  });

  testWidgets('БОШҚА (курьерсиз) хизмат рўйхатга тушмайди', (t) async {
    final cfg = {
      for (final id in kCourierConnectedModuleIds) id: ModuleStatus.enabled,
      'local_taxi': ModuleStatus.enabled,
      'realty': ModuleStatus.enabled,
    };
    expect(await idsFor(t, cfg), isNot(contains('local_taxi')));
    expect(await idsFor(t, cfg), isNot(contains('realty')));
  });

  testWidgets(
      'экран: ҳар бир хизмат учун карта, босилса ўша хизматнинг амали чақирилади',
      (t) async {
    final tapped = <String>[];
    ServiceSpotlightItem item(String id) => ServiceSpotlightItem(
          moduleId: id,
          label: 'Хизмат $id',
          onTap: () => tapped.add(id),
        );
    await t.pumpWidget(MaterialApp(
      home: CourierServicesHubScreen(
          items: [item('bread'), item('restaurants'), item('milk')]),
    ));
    for (final id in ['bread', 'restaurants', 'milk']) {
      expect(find.byKey(ValueKey('courier-hub-$id')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('courier-hub-carpet_wash')), findsNothing,
        reason: 'берилмаган хизмат йўқ');
    await t.tap(find.byKey(const ValueKey('courier-hub-restaurants')));
    await t.tap(find.byKey(const ValueKey('courier-hub-milk')));
    expect(tapped, ['restaurants', 'milk']);
    expect(t.takeException(), isNull);
  });

  testWidgets('рўйхат бўш бўлса ҳам экран синмайди', (t) async {
    await t.pumpWidget(
        const MaterialApp(home: CourierServicesHubScreen(items: [])));
    expect(t.takeException(), isNull);
  });
}
