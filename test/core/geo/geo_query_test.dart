import 'package:ava_gurlan/core/geo/geo_context.dart';
import 'package:ava_gurlan/core/geo/geo_districts_cache.dart';
import 'package:ava_gurlan/core/geo/geo_query.dart';
import 'package:ava_gurlan/core/geo/module_geo_policy.dart';
import 'package:flutter_test/flutter_test.dart';

class _Item {
  const _Item(this.id, this.districtId, this.t);
  final String id;
  final String districtId;
  final int t;
}

/// Сервер филтри даражага кўра (2-такомиллаштириш).
void main() {
  const gurlan = GeoArea(regionId: 'xorazm', districtId: 'gurlan');
  final all = [
    const _Item('a', 'gurlan', 5),
    const _Item('b', 'xiva', 4),
    const _Item('c', 'chilonzor', 3),
    const _Item('d', '', 2), // эски, ҳудудсиз
  ];
  final calls = <List<String>>[];

  Stream<List<_Item>> run(GeoLevel level, {int limit = 10, List<String>? region}) {
    calls.clear();
    return geoScopedStream<_Item>(
      scope: GeoScope(level: level, area: gurlan),
      nation: () => Stream.value(all),
      byDistricts: (ids) {
        calls.add(ids);
        return Stream.value(all.where((i) => ids.contains(i.districtId)).toList());
      },
      legacy: () => Stream.value(all.where((i) => i.districtId.isEmpty).toList()),
      idOf: (i) => i.id,
      compare: (a, b) => b.t.compareTo(a.t),
      limit: limit,
      districtsOf: (_) async => region ?? ['gurlan', 'xiva', 'urganch'],
    );
  }

  test('туман — фақат шу туман + эски ҳудудсизлар', () async {
    final l = await run(GeoLevel.district).first;
    expect(l.map((i) => i.id), ['a', 'd']);
    expect(calls, [
      ['gurlan']
    ]);
  });

  test('вилоят — вилоят туманлари бўйича (бошқа вилоят йўқ)', () async {
    final l = await run(GeoLevel.region).first;
    expect(l.map((i) => i.id), ['a', 'b', 'd']);
  });

  test('Республика — ҳаммаси, эски ҳам', () async {
    final l = await run(GeoLevel.nation).first;
    expect(l.map((i) => i.id), ['a', 'b', 'c', 'd']);
    expect(calls, isEmpty);
  });

  test('лимит ва тартиб (энг янгиси биринчи)', () async {
    final l = await run(GeoLevel.nation, limit: 2).first;
    expect(l.map((i) => i.id), ['a', 'b']);
  });

  test('30 тадан ортиқ туман — бўлакларга бўлинади', () async {
    final many = List.generate(45, (i) => 'd$i')..add('xiva');
    await run(GeoLevel.region, region: many).first;
    expect(calls.length, 2);
    expect(calls.first.length, 30);
    expect(calls.last.length, 16);
  });

  test('вилоят туманлари топилмаса — Республика (бўш экран эмас)', () async {
    final l = await run(GeoLevel.region, region: const []).first;
    expect(l.length, 4);
  });

  test('inGeoScope — қидирув учун клиент филтри', () {
    const d = GeoScope(level: GeoLevel.district, area: gurlan);
    const r = GeoScope(level: GeoLevel.region, area: gurlan);
    expect(inGeoScope('gurlan', d, const {}), isTrue);
    expect(inGeoScope('xiva', d, const {}), isFalse);
    expect(inGeoScope('', d, const {}), isTrue);
    expect(inGeoScope('xiva', r, const {'gurlan', 'xiva'}), isTrue);
    expect(inGeoScope('chilonzor', r, const {'gurlan', 'xiva'}), isFalse);
  });

  test('chunksOf', () {
    expect(chunksOf(List.generate(61, (i) => i)).map((c) => c.length), [30, 30, 1]);
  });
}
