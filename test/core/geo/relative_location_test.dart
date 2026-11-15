import 'package:ava_gurlan/core/geo/geo_names.dart';
import 'package:ava_gurlan/core/geo/relative_location.dart';
import 'package:ava_gurlan/models/geo_area.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    GeoNames.reset();
    GeoNames.remember(
      regions: const [
        GeoRegion(id: 'xorazm', name: 'Xorazm viloyati', nameUz: 'Хоразм вилояти', nameRu: 'Хорезмская область', nameRuShort: 'Хорезм'),
        GeoRegion(id: 'buxoro', name: 'Buxoro viloyati', nameUz: 'Бухоро вилояти', nameRu: 'Бухарская область', nameRuShort: 'Бухара'),
      ],
      districts: const [
        GeoDistrict(id: 'gurlan', regionId: 'xorazm', name: 'Gurlan tumani', nameUz: 'Гурлан тумани', nameRu: 'Гурленский район', nameRuShort: 'Гурлен'),
        GeoDistrict(id: 'hazorasp', regionId: 'xorazm', name: 'Hazorasp tumani', nameUz: 'Ҳазорасп тумани', nameRu: 'Хазараспский район'),
      ],
    );
  });

  tearDown(GeoNames.reset);

  String label(String d, String r, String lang) => relativeLocationLabel(
        itemDistrictId: d,
        itemRegionId: r,
        userDistrictId: 'gurlan',
        userRegionId: 'xorazm',
        lang: lang,
      );

  test('бир туман → туман қисқа номи (3 тил)', () {
    expect(label('gurlan', 'xorazm', 'uz_Cyrl'), 'Гурлан');
    expect(label('gurlan', 'xorazm', 'uz_Latn'), 'Gurlan');
    expect(label('gurlan', 'xorazm', 'ru'), 'Гурлен');
  });

  test('бир вилоят → «<туман> тумани» (3 тил)', () {
    expect(label('hazorasp', 'xorazm', 'uz_Cyrl'), 'Ҳазорасп тумани');
    expect(label('hazorasp', 'xorazm', 'uz_Latn'), 'Hazorasp tumani');
    expect(label('hazorasp', 'xorazm', 'ru'), 'Хазараспский район');
  });

  test('бошқа вилоят → вилоят номи (3 тил)', () {
    expect(label('buxoro_sh', 'buxoro', 'uz_Cyrl'), 'Бухоро вилояти');
    expect(label('buxoro_sh', 'buxoro', 'uz_Latn'), 'Buxoro viloyati');
    expect(label('buxoro_sh', 'buxoro', 'ru'), 'Бухара');
  });

  test('таснифлаш: чегара ҳолатлари', () {
    RelativeLocationKind k(String d, String r, String ud, String ur) => relativeLocationKind(
        itemDistrictId: d, itemRegionId: r, userDistrictId: ud, userRegionId: ur);
    expect(k('gurlan', '', 'gurlan', ''), RelativeLocationKind.sameDistrict);
    expect(k('hazorasp', '', 'gurlan', 'xorazm'), RelativeLocationKind.unknown);
    expect(k('', 'xorazm', 'gurlan', 'xorazm'), RelativeLocationKind.sameRegion);
    expect(k('', '', '', ''), RelativeLocationKind.unknown);
    expect(k('x', 'buxoro', '', 'xorazm'), RelativeLocationKind.otherRegion);
  });

  test('эски ҳужжат (вилоятсиз) → туман қисқа номи; кешда йўқ → fallback', () {
    expect(label('hazorasp', '', 'uz_Latn'), 'Hazorasp');
    expect(
      relativeLocationLabel(
        itemDistrictId: '',
        itemRegionId: '',
        userDistrictId: 'gurlan',
        userRegionId: 'xorazm',
        lang: 'uz_Cyrl',
        regionFallback: 'Хоразм',
      ),
      'Хоразм',
    );
  });
}
