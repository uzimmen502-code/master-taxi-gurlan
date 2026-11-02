import 'package:ava_gurlan/features/admin_web/screens/ava_service_centers_admin_screen.dart';
import 'package:ava_gurlan/models/oil_vehicle.dart';
import 'package:flutter_test/flutter_test.dart';

/// AVA Сервис маркази — ҳар туман учун битта (эга 2026-11-03).
OilServicePoint _pt(String id, {bool ava = false, String district = '', double? lat, double? lng}) =>
    OilServicePoint(
      id: id,
      name: id,
      phone: '998901234567',
      address: '',
      lat: lat,
      lng: lng,
      isAvaCenter: ava,
      districtId: district,
    );

void main() {
  test('ID туманга боғлиқ — туманга битта марказ, қайта сақлаш дубликат эмас', () {
    expect(OilServicePoint.avaCenterId('gurlan'), 'ava_gurlan');
    expect(OilServicePoint.avaCenterId(' gurlan '), 'ava_gurlan');
  });

  test('рўйхат: фақат шу туман AVA маркази, у биринчи; бошқа туманларники кўринмайди', () {
    final list = orderServicePoints([
      _pt('p1'),
      _pt('ava_urganch', ava: true, district: 'urganch'),
      _pt('ava_gurlan', ava: true, district: 'gurlan'),
      _pt('p2'),
    ], 'gurlan');
    expect(list.map((p) => p.id), ['ava_gurlan', 'p1', 'p2']);
    expect(orderServicePoints([_pt('ava_x', ava: true, district: 'x')], '').map((p) => p.id), isEmpty);
  });

  test('жой: 0,0 ёки бўш — жой йўқ', () {
    expect(_pt('a', lat: 41.5, lng: 60.6).hasLocation, isTrue);
    expect(_pt('a', lat: 0, lng: 0).hasLocation, isFalse);
    expect(_pt('a').hasLocation, isFalse);
  });

  test('toMap — мижоз ўқийдиган майдонлар', () {
    final m = _pt('a', ava: true, district: 'gurlan', lat: 41.8, lng: 60.4).toMap();
    expect(m['districtId'], 'gurlan');
    expect(m['isAvaCenter'], isTrue);
    expect(m['lat'], 41.8);
    expect(m['active'], isTrue);
  });

  group('админ киритиши', () {
    String? v({String d = 'gurlan', String n = 'AVA', String p = '+998 90 123 45 67', double? lat = 41.84, double? lng = 60.39}) =>
        validateAvaCenterInput(districtId: d, name: n, phone: p, lat: lat, lng: lng);

    test('тўғри', () => expect(v(), isNull));
    test('туман йўқ', () => expect(v(d: ''), isNotNull));
    test('ном йўқ', () => expect(v(n: ' '), isNotNull));
    test('телефон қисқа', () => expect(v(p: '12345'), isNotNull));
    test('жой белгиланмаган ёки Ўзбекистондан ташқарида', () {
      expect(v(lat: null), isNotNull);
      expect(v(lat: 0, lng: 0), isNotNull);
      expect(v(lat: 55.75, lng: 37.61), isNotNull);
    });
  });
}
