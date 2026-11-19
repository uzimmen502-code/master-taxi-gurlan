import 'package:ava_gurlan/core/geo/geo_districts_cache.dart';
import 'package:flutter_test/flutter_test.dart';

/// Эга 2026-11-19 (тезлик): «ҳалқалар» вилоят туманларини ҳар вилоят учун алоҳида сўраш ўрнига барча туманлар
/// сеансда БИР марта юкланади.
void main() {
  setUp(GeoDistrictsCache.clear);
  tearDown(GeoDistrictsCache.clear);

  test('барча туманлар бир марта юкланади, бир нечта вилоят шу кешдан', () async {
    var loads = 0;
    GeoDistrictsCache.allLoaderOverride = () async {
      loads++;
      return {
        'xorazm': ['gurlan', 'urganch'],
        'qoraqalpogiston': ['nukus'],
      };
    };
    final r = await Future.wait([
      GeoDistrictsCache.districtIdsOf('xorazm'),
      GeoDistrictsCache.districtIdsOf('qoraqalpogiston'),
      GeoDistrictsCache.districtIdsOf('xorazm'),
    ]);
    expect(r[0], ['gurlan', 'urganch']);
    expect(r[1], ['nukus']);
    expect(r[2], ['gurlan', 'urganch']);
    // Рўйхатда йўқ вилоят — қўшимча сўровсиз бўш.
    expect(await GeoDistrictsCache.districtIdsOf('mars'), isEmpty);
    expect(loads, 1);
  });

  test('бўш вилоят ID — сўровсиз бўш', () async {
    var loads = 0;
    GeoDistrictsCache.allLoaderOverride = () async {
      loads++;
      return {'xorazm': ['gurlan']};
    };
    expect(await GeoDistrictsCache.districtIdsOf('  '), isEmpty);
    expect(loads, 0);
  });

  test('барчасини юклаш хатоси — кешланмайди, кейинги чақириқ яна уринади', () async {
    var loads = 0;
    var fail = true;
    GeoDistrictsCache.allLoaderOverride = () async {
      loads++;
      if (fail) throw StateError('offline');
      return {'xorazm': ['gurlan']};
    };
    // Хатода вилоят бўйича эски йўлга тушади (тестда Firebase йўқ → бўш, кешланмайди).
    expect(await GeoDistrictsCache.districtIdsOf('xorazm'), isEmpty);
    fail = false;
    expect(await GeoDistrictsCache.districtIdsOf('qoraqalpogiston'), isEmpty);
    expect(await GeoDistrictsCache.districtIdsOf('xorazm'), anyOf(isEmpty, ['gurlan']));
    expect(loads, greaterThanOrEqualTo(2));
  });

  test('вилоят бўйича тест манбаи (loaderOverride) — аввалгидек', () async {
    GeoDistrictsCache.allLoaderOverride = () async => throw StateError('чақирилмаслиги керак');
    GeoDistrictsCache.loaderOverride = (r) async => ['d_$r'];
    expect(await GeoDistrictsCache.districtIdsOf('xorazm'), ['d_xorazm']);
  });
}
