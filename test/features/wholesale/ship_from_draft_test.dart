import 'package:ava_gurlan/features/wholesale/widgets/ship_from_fields.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ShipFromDraft.validate: viloyat → tuman → manzil (≥5) tartibida', () {
    expect(const ShipFromDraft().validate(), 'wholesale_err_region_required');
    expect(const ShipFromDraft(regionId: 'xorazm').validate(), 'wholesale_err_district_required');
    expect(const ShipFromDraft(regionId: 'xorazm', districtId: 'gurlan', address: 'abc').validate(),
        'wholesale_err_address_required');
    expect(const ShipFromDraft(regionId: 'xorazm', districtId: 'gurlan', address: 'Markaz 12').validate(), isNull);
    expect(ShipFromDraft(regionId: 'x', districtId: 'g', address: 'a' * 301).validate(),
        'wholesale_err_address_required');
  });

  test('validate(requireCoords): YANGI ro\'yxatdan o\'tishda koordinata shart va O\'zbekiston ichida (ega, 2026-10-23)', () {
    const base = ShipFromDraft(regionId: 'xorazm', districtId: 'gurlan', address: 'Markaz 12');
    // Eski sotuvchi tahriri (requireCoords yo'q) — koordinatasiz o'tadi.
    expect(base.validate(), isNull);
    expect(base.validate(requireCoords: true), 'wholesale_err_location_required');
    expect(base.copyWith(lat: 41.84).validate(requireCoords: true), 'wholesale_err_location_required', reason: 'lat yolg\'iz');
    expect(base.copyWith(lat: 41.84, lng: 60.39).validate(requireCoords: true), isNull);
    expect(base.copyWith(lat: 10, lng: 60.39).validate(requireCoords: true), 'wholesale_err_location_required');
    expect(base.copyWith(lat: 41.84, lng: 100).validate(requireCoords: true), 'wholesale_err_location_required');
    // chegara qiymatlari (rules bilan bir xil: 36..46 / 55..74)
    expect(base.copyWith(lat: 36, lng: 55).validate(requireCoords: true), isNull);
    expect(base.copyWith(lat: 46, lng: 74).validate(requireCoords: true), isNull);
    expect(base.copyWith(lat: 35.999, lng: 55).validate(requireCoords: true), 'wholesale_err_location_required');
    // avval manzil/hudud xatosi chiqadi (tartib buzilmaydi)
    expect(const ShipFromDraft().validate(requireCoords: true), 'wholesale_err_region_required');
    expect(const ShipFromDraft(regionId: 'x', districtId: 'g', address: 'abc').validate(requireCoords: true),
        'wholesale_err_address_required');
  });

  test('copyWith: viloyat o\'zgarsa tuman tozalanadi (chaqiruvchi), clearCoords', () {
    const d = ShipFromDraft(regionId: 'x', districtId: 'g', address: 'A', lat: 1, lng: 2);
    final r = d.copyWith(regionId: 'y', districtId: '');
    expect(r.regionId, 'y');
    expect(r.districtId, '');
    expect(r.lat, 1);
    final c = d.copyWith(clearCoords: true);
    expect(c.lat, isNull);
    expect(c.lng, isNull);
  });
}
