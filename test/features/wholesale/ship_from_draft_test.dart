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
