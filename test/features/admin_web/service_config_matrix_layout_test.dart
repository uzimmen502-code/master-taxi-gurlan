// Админ «Ҳудудлар ва хизматлар» матрицаси (эга, 2026-10-19: «ёзувлар жуда майдалашиб кетган — ўқиладиган қил, экранни
// тепа-пастга тортиладиган қил»): матн ўқиладиган ўлчамда (≥ 13 px), қаторлар тепа-пастга тортилади, сарлавҳа
// қатори тепада қолади, тор экранда ён томонга тортилади ва overflow йўқ.

import 'package:ava_gurlan/features/admin_web/screens/service_config_admin_screen.dart';
import 'package:ava_gurlan/models/geo_area.dart';
import 'package:ava_gurlan/models/service_module_config.dart';
import 'package:ava_gurlan/repositories/service_config_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Repo implements ServiceConfigRepository {
  _Repo({this.districts = 4});

  final int districts;

  @override
  Future<({ServiceModuleConfig config, bool enforce})> fetchModuleDefaults() async => (config: ServiceModuleConfig.empty, enforce: false);

  @override
  Future<List<GeoRegion>> fetchRegions({bool activeOnly = true}) async => const [GeoRegion(id: 'xorazm', name: 'Xorazm', nameUz: 'Хоразм')];

  @override
  Future<List<GeoDistrict>> fetchDistricts(String regionId, {bool activeOnly = true}) async => [
        for (var i = 0; i < districts; i++) GeoDistrict(id: 'd$i', regionId: regionId, name: 'Tuman $i', nameUz: 'Туман номи $i', order: i),
      ];

  @override
  Future<List<ServiceArea>> fetchServiceAreasForRegion(String regionId, {bool activeOnly = true}) async => [
        for (var i = 0; i < districts; i++) ServiceArea(id: 'a$i', districtId: 'd$i', regionId: regionId, name: 'MFY $i', nameUz: 'МФЙ $i', order: i),
      ];

  @override
  Future<Map<String, ({ServiceModuleConfig config, Set<String> manualModules})>> fetchAreaModulesBatch(Iterable<String> ids) async => {};

  @override
  Future<Map<String, ({ServiceModuleConfig config, Set<String> manualModules})>> fetchDistrictModulesBatch(Iterable<String> ids) async => {};

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  Future<void> pump(WidgetTester t, {required double width, int districts = 4}) async {
    t.view.physicalSize = Size(width * 2, 800 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: ServiceConfigAdminScreen(repository: _Repo(districts: districts)))));
    await t.pumpAndSettle();
  }

  double fontOf(WidgetTester t, String text) {
    final w = t.widget<Text>(find.text(text).first);
    return w.style?.fontSize ?? 14;
  }

  testWidgets('матн ўқиладиган ўлчамда: модул номи ≥ 14 px, ҳолат катаги ≥ 14 px, сарлавҳа ≥ 12 px', (t) async {
    await pump(t, width: 1280);
    expect(t.takeException(), isNull);
    expect(fontOf(t, 'Mahalliy taksi'), greaterThanOrEqualTo(14));
    expect(fontOf(t, 'Baseline'), greaterThanOrEqualTo(12));
    // Ҳолат катагининг матни (барча модуллар «Ёпиқ/мерос» ва ҳ.к.) — биринчи қатордаги катак.
    final cellTexts = t.widgetList<Text>(find.descendant(of: find.byKey(const ValueKey('matrix-rows-scroll')), matching: find.byType(Text)));
    expect(cellTexts, isNotEmpty);
    for (final c in cellTexts) {
      expect(c.style?.fontSize ?? 14, greaterThanOrEqualTo(14), reason: c.data);
    }
  });

  testWidgets('қаторлар тепа-пастга тортилади: охирги модул аввал кўринмайди, тортилса кўринади; сарлавҳа жойида қолади', (t) async {
    await pump(t, width: 1280);
    final headerBefore = t.getTopLeft(find.text('Baseline').first);
    final last = find.text('Уста чақириш (қидирувдан сўров)');
    expect(last, findsOneWidget, reason: 'ленивый эмас — қурилган');
    expect(t.getTopLeft(last).dy, greaterThan(800), reason: 'экрандан пастда');
    await t.drag(find.byKey(const ValueKey('matrix-rows-scroll')), const Offset(0, -2000));
    await t.pumpAndSettle();
    expect(t.getTopLeft(last).dy, lessThan(800), reason: 'тортилгандан кейин кўринади');
    expect(t.getTopLeft(find.text('Baseline').first).dy, headerBefore.dy, reason: 'сарлавҳа қатори тепада қолди');
    expect(t.takeException(), isNull);
  });

  testWidgets('тор админ экран (1000) ва кўп туман: ён томонга тортилади, overflow йўқ', (t) async {
    await pump(t, width: 1000, districts: 12);
    expect(t.takeException(), isNull);
    expect(find.byType(Scrollbar), findsWidgets);
  });
}
