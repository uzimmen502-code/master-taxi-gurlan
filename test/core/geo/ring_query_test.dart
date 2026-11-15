import 'package:ava_gurlan/core/geo/geo_context.dart';
import 'package:ava_gurlan/core/geo/module_geo_policy.dart';
import 'package:ava_gurlan/core/geo/region_centers.dart';
import 'package:ava_gurlan/core/geo/ring_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('regionRingOrder', () {
    test('14 вилоят, такрорсиз', () {
      final o = regionRingOrder('xorazm');
      expect(o.length, 14);
      expect(o.toSet().length, 14);
      expect(o.toSet(), kRegionCenters.keys.toSet());
    });

    test('Хоразм: xorazm биринчи, кейин Қорақалпоғистон', () {
      final o = regionRingOrder('xorazm');
      expect(o.take(2), ['xorazm', 'qoraqalpogiston']);
      // Водий — энг узоқда.
      expect(o.indexOf('andijon'), greaterThan(o.indexOf('buxoro')));
    });

    test('Тошкент шаҳри: вилоят дарҳол кейин', () {
      final o = regionRingOrder('toshkent_shahri');
      expect(o.take(2), ['toshkent_shahri', 'toshkent_viloyati']);
      expect(o.last, 'qoraqalpogiston');
    });

    test('номаълум вилоят — барқарор алифбо', () {
      final sorted = kRegionCenters.keys.toList()..sort();
      expect(regionRingOrder(''), sorted);
      expect(regionRingOrder('  '), sorted);
      expect(regionRingOrder('mars'), ['mars', ...sorted]);
    });

    test('haversine: Урганч–Нукус ≈ 130 км', () {
      final km = haversineKm(kRegionCenters['xorazm']!, kRegionCenters['qoraqalpogiston']!);
      expect(km, inInclusiveRange(110, 150));
      expect(haversineKm((41.0, 60.0), (41.0, 60.0)), 0);
    });
  });

  group('buildRingPlan / buildRingSteps', () {
    final byRegion = {
      'xorazm': ['gurlan', 'urganch', 'xiva'],
      'qoraqalpogiston': ['nukus', 'beruniy'],
      'buxoro': ['buxoro_sh'],
    };

    test('туман → вилоят қолгани → бошқа вилоятлар масофа бўйича', () {
      final plan = buildRingPlan(userDistrictId: 'gurlan', userRegionId: 'xorazm');
      expect(plan.first, const RingStepSpec(ring: 0, regionId: 'xorazm', onlyDistrictId: 'gurlan'));
      expect(plan[1], const RingStepSpec(ring: 1, regionId: 'xorazm', excludeDistrictId: 'gurlan'));
      expect(plan[2].regionId, 'qoraqalpogiston');
      expect(plan[2].ring, 2);
      expect(plan.length, 1 + 14);

      final steps = buildRingSteps(plan, byRegion);
      expect(steps[0].ring, 0);
      expect(steps[0].districtIds, ['gurlan']);
      expect(steps[1].districtIds, ['urganch', 'xiva']);
      expect(steps[2].districtIds, ['nukus', 'beruniy']);
      // Туманлари маълум бўлмаган вилоятлар — бўш қадам ташланади.
      expect(steps.map((s) => s.ring).toList(), [0, 1, 2, plan.firstWhere((s) => s.regionId == 'buxoro').ring]);
    });

    test('туман номаълум — ring 0 йўқ, вилоят бутун', () {
      final plan = buildRingPlan(userDistrictId: '', userRegionId: 'xorazm');
      expect(plan.first.ring, 1);
      expect(buildRingSteps(plan, byRegion).first.districtIds, ['gurlan', 'urganch', 'xiva']);
    });

    test('ҳеч нарса номаълум — 14 вилоят алифбода, ring 2 дан', () {
      final plan = buildRingPlan(userDistrictId: '', userRegionId: '');
      expect(plan.length, 14);
      expect(plan.first.ring, 2);
      expect(plan.first.regionId, 'andijon');
    });

    test('аниқ танлов — битта ҳалқа', () {
      const a = GeoArea(regionId: 'xorazm', districtId: 'gurlan');
      expect(ringPlanFor(const GeoScope(level: GeoLevel.district, area: a)),
          [const RingStepSpec(ring: 0, regionId: 'xorazm', onlyDistrictId: 'gurlan')]);
      expect(ringPlanFor(const GeoScope(level: GeoLevel.region, area: a)),
          [const RingStepSpec(ring: 0, regionId: 'xorazm')]);
      expect(ringPlanFor(const GeoScope(level: GeoLevel.nation, area: a)).length, 15);
      expect(explicitRingPlan(districtId: '', regionId: ''), isEmpty);
    });
  });

  group('RingPager', () {
    // Сохта манба: туман → ҳужжатлар (янгиси биринчи). Курсор — индекс.
    final data = {
      'gurlan': ['g1', 'g2', 'g3'],
      'urganch': ['u1'],
      'xiva': <String>[],
      'nukus': ['n1', 'n2'],
    };
    final regions = {
      'xorazm': ['gurlan', 'urganch', 'xiva'],
      'qoraqalpogiston': ['nukus'],
    };

    late List<List<String>> calls;
    late int regionLoads;

    RingPager<String> pager(List<RingStepSpec> plan, {int chunk = 30}) => RingPager<String>(
          plan: plan,
          chunkSize: chunk,
          districtsOf: (r) async {
            regionLoads++;
            return regions[r] ?? const [];
          },
          fetch: (ids, after, limit) async {
            calls.add(ids);
            final all = [for (final d in ids) ...data[d] ?? const <String>[]];
            final start = after == null ? 0 : (after as int) + 1;
            final page = all.skip(start).take(limit).toList();
            return RingFetchResult(page, page.isEmpty ? after : start + page.length - 1);
          },
        );

    setUp(() {
      calls = [];
      regionLoads = 0;
    });

    test('ҳалқама-ҳалқа, ҳалқа рақами билан; тугагач hasMore=false', () async {
      final p = pager(buildRingPlan(userDistrictId: 'gurlan', userRegionId: 'xorazm'));
      final first = await p.next(2);
      expect(first.map((e) => e.item), ['g1', 'g2']);
      expect(first.every((e) => e.ring == 0), isTrue);
      expect(regionLoads, 0, reason: 'ring 0 вилоят юкламайди');

      final second = await p.next(3);
      expect(second.map((e) => e.item), ['g3', 'u1', 'n1']);
      expect(second.map((e) => e.ring), [0, 1, 2]);
      expect(calls[2], ['urganch', 'xiva'], reason: 'ring 1 — gurlan чиқарилган');

      final rest = await p.next(50);
      expect(rest.map((e) => e.item), ['n2']);
      expect(p.hasMore, isFalse);
      expect(await p.next(5), isEmpty);
    });

    test('30 дан кўп туман — бўлакларга', () async {
      final p = pager([const RingStepSpec(ring: 0, regionId: 'xorazm')], chunk: 2);
      final items = await p.next(10);
      expect(items.map((e) => e.item), ['g1', 'g2', 'g3', 'u1']);
      expect(calls.first, ['gurlan', 'urganch']);
      expect(calls.last, ['xiva']);
    });

    test('сўров хатоси — ҳолат ўзгармайди, қайта чақириш давом этади', () async {
      var fail = true;
      final p = RingPager<String>(
        plan: const [RingStepSpec(ring: 0, regionId: 'xorazm', onlyDistrictId: 'gurlan')],
        districtsOf: (_) async => const [],
        fetch: (ids, after, limit) async {
          if (fail) throw StateError('offline');
          return RingFetchResult(data['gurlan']!.take(limit).toList(), null);
        },
      );
      await expectLater(p.next(2), throwsStateError);
      fail = false;
      expect((await p.next(2)).map((e) => e.item), ['g1', 'g2']);
    });

    test('параллел next — навбатда, такрорсиз', () async {
      final p = pager(buildRingPlan(userDistrictId: 'gurlan', userRegionId: 'xorazm'));
      final r = await Future.wait([p.next(2), p.next(2)]);
      expect(r[0].map((e) => e.item), ['g1', 'g2']);
      expect(r[1].map((e) => e.item), ['g3', 'u1']);
    });
  });

  group('GeoMode.rings сиёсати', () {
    const ids = [
      'livestock_market',
      'auto_market',
      'meat_market',
      'farm_market',
      'wholesale_market',
      'china_market',
      'realty',
    ];

    test('7 модул — rings', () {
      for (final id in ids) {
        expect(geoPolicyFor(id).mode, GeoMode.rings, reason: id);
      }
    });

    test('Аралаш бозор ва бошқалар ўзгармаган', () {
      expect(geoPolicyFor('cheap_products_home').mode, GeoMode.tiered);
      expect(geoPolicyFor('tv_market').mode, GeoMode.tiered);
      expect(geoPolicyFor('jobs').mode, GeoMode.tiered);
    });

    test('7-босқич (эга 2026-11-15): Улгуржи/Хитой/Уй-жой — сукут Республика ҳалқалари, вилоят/туман танлови, сақланмайди', () {
      for (final id in ['wholesale_market', 'china_market', 'realty']) {
        final p = geoPolicyFor(id);
        expect(p.levels, [GeoLevel.nation, GeoLevel.region, GeoLevel.district], reason: id);
        expect(p.defaultLevel, GeoLevel.nation, reason: id);
        expect(p.persistSelection, isFalse, reason: id);
      }
      expect(geoPolicyFor('realty').usesLocation, isTrue);
    });

    test('янги бозорлар: сукут Республика (ҳалқалар), танлов сақланмайди', () {
      for (final id in ids.take(4)) {
        final p = geoPolicyFor(id);
        expect(p.defaultLevel, GeoLevel.nation, reason: id);
        expect(p.persistSelection, isFalse, reason: id);
      }
    });
  });
}
