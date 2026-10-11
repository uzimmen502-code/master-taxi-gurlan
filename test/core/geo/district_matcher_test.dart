import 'package:ava_gurlan/core/geo/district_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

/// D-GEO-13 (А вариант): geocoder номи → `geo_districts`. Номлар базадаги
/// каби (`name` лотин, `nameUz` кирилл — seed-national-geo / seed-service-config).
void main() {
  const districts = [
    DistrictCandidate(id: 'gurlan', regionId: 'xorazm', names: ['Gurlan tumani', 'Гурлан тумани']),
    DistrictCandidate(id: 'urganch_sh', regionId: 'xorazm', names: ['Urganch shahri', 'Урганч шаҳри']),
    DistrictCandidate(id: 'urganch', regionId: 'xorazm', names: ['Urganch tumani', 'Урганч тумани']),
    DistrictCandidate(id: 'xiva', regionId: 'xorazm', names: ['Xiva tumani', 'Хива тумани']),
    DistrictCandidate(id: 'chilonzor', regionId: 'toshkent_shahri', names: ['Chilonzor tumani', 'Чилонзор тумани']),
    DistrictCandidate(id: 'yunusobod', regionId: 'toshkent_shahri', names: ['Yunusobod tumani', 'Юнусобод тумани']),
    DistrictCandidate(id: 'mirzo_ulugbek', regionId: 'toshkent_shahri', names: ['Mirzo Ulugʻbek tumani', 'Мирзо Улуғбек тумани']),
    DistrictCandidate(id: 'shayxontoxur', regionId: 'toshkent_shahri', names: ['Shayxontoxur tumani', 'Шайхонтоҳур тумани']),
    DistrictCandidate(id: 'qibray', regionId: 'toshkent_viloyati', names: ['Qibray tumani', 'Қибрай тумани']),
  ];
  const regions = [
    RegionCandidate(id: 'xorazm', names: ['Xorazm viloyati', 'Хоразм вилояти']),
    RegionCandidate(id: 'toshkent_shahri', names: ['Toshkent shahri', 'Тошкент шаҳри']),
    RegionCandidate(id: 'toshkent_viloyati', names: ['Toshkent viloyati', 'Тошкент вилояти']),
    RegionCandidate(id: 'samarqand', names: ['Samarqand viloyati', 'Самарқанд вилояти']),
  ];

  String? d(List<String?> c, {List<String> r = const []}) => matchDistrict(c, districts, regionIds: r)?.id;

  group('скелет', () {
    test('ёзилиш фарқлари бир хил калитга келади', () {
      expect(nameSkeleton('Гурленский район'), nameSkeleton('Gurlan tumani'));
      expect(nameSkeleton('Chilanzar District'), nameSkeleton('Чилонзор тумани'));
      expect(nameSkeleton('Юнусабадский район'), nameSkeleton('Yunusobod tumani'));
      expect(nameSkeleton('Khiva'), nameSkeleton('Хива тумани'));
      expect(nameSkeleton('Shaykhantakhur District'), nameSkeleton('Shayxontoxur tumani'));
      expect(nameSkeleton('Mirzo-Ulugbek District'), nameSkeleton('Mirzo Ulugʻbek tumani'));
    });
    test('бошқа туманлар бир хил калит бермайди', () {
      expect(nameSkeleton('Gurlan'), isNot(nameSkeleton('Xiva')));
      expect(nameSkeleton('Chilonzor'), isNot(nameSkeleton('Yunusobod')));
    });
  });

  group('туман', () {
    test('ўзбекча (лотин/кирилл), русча, инглизча — топилади', () {
      expect(d(['Gurlan tumani']), 'gurlan');
      expect(d(['Гурлан тумани']), 'gurlan');
      expect(d(['Гурленский район']), 'gurlan');
      expect(d(['Gurlan District']), 'gurlan');
      expect(d(['Chilanzar District']), 'chilonzor');
      expect(d(['Чиланзарский район']), 'chilonzor');
    });
    test('биринчи майдон бўш/номаълум — кейингиси кўрилади', () {
      expect(d([null, '', 'Yunusabad']), 'yunusobod');
      expect(d(['Tashkent', 'Yunusabad District'], r: ['toshkent_shahri']), 'yunusobod');
    });
    test('шаҳар ва туман бир хил номда (Урганч) — таклиф ЙЎҚ (эҳтиёткор)', () {
      expect(d(['Urgench']), isNull);
      expect(d(['Ургенч'], r: ['xorazm']), isNull);
    });
    test('топилмаса — null', () {
      expect(d(['Samarkand']), isNull);
      expect(d(['ab']), isNull);
      expect(d([]), isNull);
    });
    test('вилоят чеклови: бошқа вилоят тумани олинмайди', () {
      expect(d(['Gurlan District'], r: ['toshkent_shahri']), isNull);
    });
  });

  group('вилоят', () {
    test('Тошкент — шаҳар ва вилоят иккаласи (туман ажратади)', () {
      expect(matchRegions('Tashkent', regions).toSet(), {'toshkent_shahri', 'toshkent_viloyati'});
      expect(d(['Qibray District'], r: matchRegions('Ташкентская область', regions)), 'qibray');
    });
    test('Хоразм — Khorezm / Хорезмская область', () {
      expect(matchRegions('Khorezm Region', regions), ['xorazm']);
      expect(matchRegions('Хорезмская область', regions), ['xorazm']);
      expect(matchRegions('Xorazm viloyati', regions), ['xorazm']);
    });
    test('номаълум — бўш', () {
      expect(matchRegions(null, regions), isEmpty);
      expect(matchRegions('Kazakhstan', regions), isEmpty);
    });
  });
}
