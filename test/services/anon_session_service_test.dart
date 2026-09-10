import 'package:ava_gurlan/services/anon_session_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolvePreselectedGeo', () {
    test('ServiceConfigHolder statiklari to\'liq bo\'lsa — ular ustunlik '
        'qiladi (prefs e\'tiborga olinmaydi)', () {
      final geo = resolvePreselectedGeo(
        holderRegionId: 'r1',
        holderDistrictId: 'd1',
        holderServiceAreaId: 'a1',
        prefsRegionId: 'r2',
        prefsDistrictId: 'd2',
        prefsServiceAreaId: 'a2',
      );
      expect(geo.regionId, 'r1');
      expect(geo.districtId, 'd1');
      expect(geo.serviceAreaId, 'a1');
    });

    test('ServiceConfigHolder bo\'sh bo\'lsa — pre_onboarding_* prefs '
        'ishlatiladi', () {
      final geo = resolvePreselectedGeo(
        holderRegionId: '',
        holderDistrictId: '',
        holderServiceAreaId: '',
        prefsRegionId: 'r2',
        prefsDistrictId: 'd2',
        prefsServiceAreaId: 'a2',
      );
      expect(geo.regionId, 'r2');
      expect(geo.districtId, 'd2');
      expect(geo.serviceAreaId, 'a2');
    });

    test('faqat region bor, district yo\'q (holder to\'liqsiz) — baribir '
        'prefs\'ga fallback qilinadi', () {
      final geo = resolvePreselectedGeo(
        holderRegionId: 'r1',
        holderDistrictId: '',
        holderServiceAreaId: 'a1',
        prefsRegionId: 'r2',
        prefsDistrictId: 'd2',
        prefsServiceAreaId: 'a2',
      );
      expect(geo.regionId, 'r2');
      expect(geo.districtId, 'd2');
    });

    test('ikkalasi ham bo\'sh — bo\'sh string qaytadi (crash emas)', () {
      final geo = resolvePreselectedGeo(
        holderRegionId: '',
        holderDistrictId: '',
        holderServiceAreaId: '',
        prefsRegionId: '',
        prefsDistrictId: '',
        prefsServiceAreaId: '',
      );
      expect(geo.regionId, '');
      expect(geo.districtId, '');
      expect(geo.serviceAreaId, '');
    });

    test('bo\'shliqlar trim qilinadi', () {
      final geo = resolvePreselectedGeo(
        holderRegionId: '  r1  ',
        holderDistrictId: '  d1  ',
        holderServiceAreaId: '  a1  ',
        prefsRegionId: '',
        prefsDistrictId: '',
        prefsServiceAreaId: '',
      );
      expect(geo.regionId, 'r1');
      expect(geo.districtId, 'd1');
      expect(geo.serviceAreaId, 'a1');
    });
  });
}
