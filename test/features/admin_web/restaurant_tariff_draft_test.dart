import 'package:ava_gurlan/features/admin_web/utils/restaurant_tariff_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('hujjatdan qoralama: raqamlar matn, mintaqa yoqilgan/yo\'q, versiya', () {
    final d = RestaurantTariffDraft.fromDoc({
      'base': 5000, 'perKm': 1500, 'nightCoef': 1.5, 'nightStart': 23, 'nightEnd': 6, 'roadFactor': 1.3, 'maxKm': 15,
      'version': 3, 'updatedBy': '998901110000',
      'regions': {'xorazm': {'base': 4500, 'perKm': 1200, 'maxKm': 20}},
    });
    expect(d.base, '5000');
    expect(d.perKm, '1500');
    expect(d.nightCoef, '1.5');
    expect(d.nightStart, '23');
    expect(d.maxKm, '15');
    expect(d.version, 3);
    expect(d.isConfigured, isTrue);
    expect(d.regions['xorazm']!.enabled, isTrue);
    expect(d.regions['xorazm']!.base, '4500');
    expect(d.regions['xorazm']!.maxKm, '20');
    expect(d.regions['tashkent']!.enabled, isFalse);
    expect(d.regions.keys.toSet(), kRestaurantTariffRegions.keys.toSet());
  });

  test('hujjat yo\'q → bo\'sh qoralama, sozlanmagan; validatsiya bazani talab qiladi', () {
    final d = RestaurantTariffDraft.fromDoc(null);
    expect(d.isConfigured, isFalse);
    expect(d.base, '');
    expect(d.validate(), isNotEmpty);
  });

  test('validatsiya: server bilan bir xil chegaralar', () {
    final ok = RestaurantTariffDraft(base: '5000', perKm: '1500');
    expect(ok.validate(), isEmpty, reason: 'faqat baza + km yetarli');
    expect(RestaurantTariffDraft(base: '0', perKm: '1500').validate(), isNotEmpty);
    expect(RestaurantTariffDraft(base: '5000', perKm: '-1').validate(), isNotEmpty);
    expect(RestaurantTariffDraft(base: '5000.5', perKm: '1500').validate(), isNotEmpty, reason: 'butun so\'m');
    expect(RestaurantTariffDraft(base: '5000', perKm: '1500', nightCoef: '5').validate(), isNotEmpty);
    expect(RestaurantTariffDraft(base: '5000', perKm: '1500', nightCoef: '1,5').validate(), isEmpty, reason: 'vergul ham');
    expect(RestaurantTariffDraft(base: '5000', perKm: '1500', nightStart: '24').validate(), isNotEmpty);
    expect(RestaurantTariffDraft(base: '5000', perKm: '1500', roadFactor: '2.5').validate(), isNotEmpty);
    expect(RestaurantTariffDraft(base: '5000', perKm: '1500', maxKm: '0').validate(), isNotEmpty);
    final badRegion = RestaurantTariffDraft(base: '5000', perKm: '1500');
    badRegion.regions['xorazm']!
      ..enabled = true
      ..base = ''
      ..perKm = '1000';
    expect(badRegion.validate(), isNotEmpty, reason: 'yoqilgan mintaqada baza shart');
    badRegion.regions['xorazm']!.enabled = false;
    expect(badRegion.validate(), isEmpty, reason: 'o\'chirilgan mintaqa tekshirilmaydi');
  });

  test('payload: faqat to\'ldirilganlar, sonlar son, mintaqalar faqat yoqilganlar', () {
    final d = RestaurantTariffDraft(base: '5000', perKm: '1500', nightCoef: '1,5', nightStart: '23', maxKm: '15');
    d.regions['xorazm']!
      ..enabled = true
      ..base = '4500'
      ..perKm = '1200'
      ..maxKm = '20';
    d.regions['tashkent']!
      ..enabled = false
      ..base = '9000'
      ..perKm = '3000';
    final p = d.toPayload(reason: ' yoqilg\'i ');
    expect(p['base'], 5000);
    expect(p['perKm'], 1500);
    expect(p['nightCoef'], 1.5);
    expect(p['nightStart'], 23);
    expect(p.containsKey('nightEnd'), isFalse, reason: 'bo\'sh maydon yuborilmaydi — serverdagi qoladi');
    expect(p.containsKey('roadFactor'), isFalse);
    expect(p['maxKm'], 15);
    expect(p['reason'], 'yoqilg\'i');
    expect(p['regions'], {'xorazm': {'base': 4500, 'perKm': 1200, 'maxKm': 20}});
  });
}
