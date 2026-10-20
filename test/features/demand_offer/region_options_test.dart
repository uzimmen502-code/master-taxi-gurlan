// Респуб. миқёси: таклифчи экранида ҳудуд чиплари `geo_regions` дан (14 вилоят),
// қаттиқ ['xorazm'] эмас. Бу — шу рўйхатни қуриш ва бошланғич танловни
// аниқлаш логикаси (тоза функциялар, Firestore йўқ).
import 'package:ava_gurlan/features/demand_offer/domain/region_options.dart';
import 'package:ava_gurlan/models/geo_area.dart';
import 'package:flutter_test/flutter_test.dart';

GeoRegion r(String id, String name, String nameUz, String nameRu,
        {int order = 0, bool active = true}) =>
    GeoRegion(
      id: id,
      name: name,
      nameUz: nameUz,
      nameRu: nameRu,
      order: order,
      active: active,
    );

void main() {
  final regions = [
    r('toshkent_shahri', 'Toshkent shahri', 'Тошкент шаҳри', 'город Ташкент',
        order: 2),
    r('xorazm', 'Xorazm', 'Хоразм', 'Хорезм', order: 1),
    r('andijon', 'Andijon', 'Андижон', 'Андижан', order: 3),
  ];

  group('buildRegionOptions', () {
    test('barcha faol viloyat — `order` tartibida (qat`iy xorazm emas)', () {
      final o = buildRegionOptions(regions, 'uz_Latn');
      expect(o.map((e) => e.id).toList(),
          ['xorazm', 'toshkent_shahri', 'andijon']);
    });

    test('yorliq foydalanuvchi tilida', () {
      expect(buildRegionOptions(regions, 'uz_Cyrl').first.label, 'Хоразм');
      expect(buildRegionOptions(regions, 'uz_Latn').first.label, 'Xorazm');
      expect(buildRegionOptions(regions, 'ru').first.label, 'Хорезм');
    });

    test('rus tilida «город » olib tashlanadi', () {
      final o = buildRegionOptions(regions, 'ru');
      expect(o.firstWhere((e) => e.id == 'toshkent_shahri').label, 'Ташкент');
    });

    test('faol bo`lmagan viloyat ko`rsatilmaydi', () {
      final o = buildRegionOptions(
        [...regions, r('yopiq', 'Yopiq', 'Ёпиқ', 'Закрыт', active: false)],
        'uz_Latn',
      );
      expect(o.any((e) => e.id == 'yopiq'), isFalse);
    });

    test('`_` li ID (toshkent_shahri) saqlanadi', () {
      final o = buildRegionOptions(regions, 'uz_Latn');
      expect(o.any((e) => e.id == 'toshkent_shahri'), isTrue);
    });

    test('bo`sh ro`yxat -> bo`sh', () {
      expect(buildRegionOptions(const [], 'uz_Latn'), isEmpty);
    });

    test('nomi bo`sh bo`lsa ID ko`rsatiladi (hech qachon bo`sh yorliq emas)', () {
      final o = buildRegionOptions([r('noname', '', '', '')], 'uz_Latn');
      expect(o.single.label, 'noname');
    });
  });

  group('resolveInitialRegions', () {
    const options = ['xorazm', 'toshkent_shahri', 'andijon'];

    test('berilgan boshlang`ich tanlov (ro`yxatda bo`lsa) ishlatiladi', () {
      expect(
        resolveInitialRegions(
            initial: ['toshkent_shahri'], userRegion: 'xorazm', options: options),
        {'toshkent_shahri'},
      );
    });

    test('ro`yxatda yo`q ID tashlab yuboriladi', () {
      expect(
        resolveInitialRegions(
            initial: ['atlantida', 'andijon'], userRegion: null, options: options),
        {'andijon'},
      );
    });

    test('boshlang`ich yo`q -> foydalanuvchining o`z viloyati', () {
      expect(
        resolveInitialRegions(
            initial: const [], userRegion: 'andijon', options: options),
        {'andijon'},
      );
    });

    test('foydalanuvchi viloyati ro`yxatda yo`q -> bo`sh (foydalanuvchi tanlaydi)', () {
      expect(
        resolveInitialRegions(
            initial: const [], userRegion: 'atlantida', options: options),
        isEmpty,
      );
    });

    test('hech narsa yo`q -> bo`sh; avtomatik «xorazm» TANLANMAYDI', () {
      final s = resolveInitialRegions(
          initial: const [], userRegion: null, options: options);
      expect(s, isEmpty);
      expect(s.contains('xorazm'), isFalse);
    });

    test('bo`sh yoki probelli userRegion e`tiborga olinmaydi', () {
      expect(
        resolveInitialRegions(initial: const [], userRegion: '  ', options: options),
        isEmpty,
      );
    });
  });
}
