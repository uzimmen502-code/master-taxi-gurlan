import 'package:ava_gurlan/features/yuk_local/models/yuk_local_driver.dart';
import 'package:flutter_test/flutter_test.dart';

YukLocalDriver _d(Map<String, dynamic> extra) =>
    YukLocalDriver.fromFirestore('id1', {
      'ownerId': '998901234567',
      'vehicleType': 'labo',
      'lat': 41.0,
      'lng': 60.0,
      ...extra,
    });

void main() {
  group('YukLocalDriver — hudud maydoni', () {
    test('districtId / regionId hujjatdan o‘qiladi', () {
      final d = _d({'districtId': 'gurlan', 'regionId': 'xorazm'});
      expect(d.districtId, 'gurlan');
      expect(d.regionId, 'xorazm');
      expect(d.hasNoDistrict, isFalse);
    });

    test('eski yozuvda maydon yo‘q — hasNoDistrict true', () {
      final d = _d({});
      expect(d.districtId, '');
      expect(d.regionId, '');
      // Backfill'gacha shunday yozuvlar barcha tumanda ko'rinadi.
      expect(d.hasNoDistrict, isTrue);
    });

    test('bo‘shliqlar trim qilinadi', () {
      final d = _d({'districtId': '  gurlan  '});
      expect(d.districtId, 'gurlan');
      expect(d.hasNoDistrict, isFalse);
    });

    test('faqat bo‘shliqdan iborat qiymat — hududsiz', () {
      expect(_d({'districtId': '   '}).hasNoDistrict, isTrue);
    });

    test('copyWith hududni saqlaydi va almashtiradi', () {
      final d = _d({'districtId': 'gurlan', 'regionId': 'xorazm'});
      expect(d.copyWith().districtId, 'gurlan');
      expect(d.copyWith(districtId: 'xiva').districtId, 'xiva');
      expect(d.copyWith(districtId: 'xiva').regionId, 'xorazm');
    });
  });
}
