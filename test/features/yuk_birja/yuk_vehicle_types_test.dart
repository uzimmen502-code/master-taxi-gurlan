import 'package:ava_gurlan/features/yuk_birja/yuk_vehicle_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeYukVehicleType', () {
    test('бўш → fura (default)', () {
      expect(normalizeYukVehicleType(''), 'fura');
      expect(normalizeYukVehicleType('   '), 'fura');
    });

    test('барқарор код ўзгармайди', () {
      for (final t in kYukVehicleTypes) {
        expect(normalizeYukVehicleType(t.value), t.value);
      }
    });

    test('legacy кириллча қийматлар кодга айланади', () {
      expect(normalizeYukVehicleType('фура'), 'fura');
      expect(normalizeYukVehicleType('рефрижератор'), 'ref');
      expect(normalizeYukVehicleType('газель'), 'gazel');
      expect(normalizeYukVehicleType('юк мотоцикли'), 'moto');
      expect(normalizeYukVehicleType('трактор'), 'traktor');
      expect(normalizeYukVehicleType('исудзу'), 'isuzu');
      expect(normalizeYukVehicleType('isuzi'), 'isuzu');
    });

    test('номаълум → other', () {
      expect(normalizeYukVehicleType('ракета'), 'other');
    });

    test('trim қилинади', () {
      expect(normalizeYukVehicleType('  gazel '), 'gazel');
    });
  });

  group('local / intercity рўйхатлари', () {
    test('local — тўлиқ рўйхат, moto биринчи', () {
      final local = yukVehicleTypesForLocal();
      expect(local.length, kYukVehicleTypes.length);
      expect(local.first.value, 'moto');
    });

    test('intercity — moto/traktor йўқ, қолгани бор', () {
      final inter = yukVehicleTypesForIntercity().map((t) => t.value).toSet();
      expect(inter, isNot(contains('moto')));
      expect(inter, isNot(contains('traktor')));
      expect(inter.length,
          kYukVehicleTypes.length - kYukLocalOnlyVehicleValues.length);
      expect(inter, containsAll(['fura', 'ref', 'gazel', 'other']));
    });

    test('normalizeYukVehicleTypeForIntercity: local-only → fura', () {
      expect(normalizeYukVehicleTypeForIntercity('moto'), 'fura');
      expect(normalizeYukVehicleTypeForIntercity('трактор'), 'fura');
      expect(normalizeYukVehicleTypeForIntercity('gazel'), 'gazel');
    });

    test('yukVehicleListPriority: moto 0, қолгани 1', () {
      expect(yukVehicleListPriority('moto'), 0);
      expect(yukVehicleListPriority('юк мотоцикл'), 0);
      expect(yukVehicleListPriority('fura'), 1);
      expect(yukVehicleListPriority('traktor'), 1);
    });
  });

  group('yukVehicleLabelKey', () {
    test('код → i18n калит', () {
      expect(yukVehicleLabelKey('gazel'), 'yuk_vehicle_gazel');
      expect(yukVehicleLabelKey('газель'), 'yuk_vehicle_gazel');
      expect(yukVehicleLabelKey('nimadir'), 'yuk_vehicle_other');
    });
  });
}
