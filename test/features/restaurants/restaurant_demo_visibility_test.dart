import 'package:ava_gurlan/features/restaurants/data/restaurants_repository.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Намуна ресторанлар (эга қарори, 2026-10-23): фойдаланувчи қайси туманда бўлса ҳам кўринади — ҳақиқийлардан кейин,
/// бошқа туманда масофа кўрсатилмайди.
Restaurant _r(String id, double lat, double lng, {bool demo = false}) => Restaurant(
      id: id,
      name: id,
      status: 'approved',
      lat: lat,
      lng: lng,
      isDemo: demo,
    );

void main() {
  // Фойдаланувчи — Самарқанд; намуналар — Гурлан ва Тошкентда.
  const uLat = 39.65;
  const uLng = 66.96;

  test('fromMap: isDemo faqat true bo\'lganda', () {
    expect(Restaurant.fromMap('a', const {'isDemo': true}).isDemo, isTrue);
    expect(Restaurant.fromMap('a', const {'isDemo': 'true'}).isDemo, isFalse);
    expect(Restaurant.fromMap('a', const {}).isDemo, isFalse);
  });

  test('namuna uzoqda ham ro\'yxatda — haqiqiylardan keyin', () {
    final real = _r('real_near', 39.66, 66.97);
    final realFar = _r('real_far', 41.31, 69.28); // Тошкент, >20 км — чиқмайди
    final demoGurlan = _r('demo_gurlan', 41.84, 60.39, demo: true);
    final demoTashkent = _r('demo_tashkent', 41.31, 69.28, demo: true);

    final out = RestaurantsRepository.withinRadius(
      [demoTashkent, realFar, demoGurlan, real],
      uLat,
      uLng,
      RestaurantsRepository.nearbyRadiusKm,
    );
    expect(out.map((r) => r.id), ['real_near', 'demo_gurlan', 'demo_tashkent']);
  });

  test('namuna yo\'q — eski xatti-harakat o\'zgarmagan (faqat radius ichidagilar, yaqini birinchi)', () {
    final a = _r('a', 39.70, 66.96); // ~5.5 км
    final b = _r('b', 39.66, 66.96); // ~1.1 км
    final c = _r('c', 41.0, 69.0);
    final out = RestaurantsRepository.withinRadius([a, b, c], uLat, uLng, 20);
    expect(out.map((r) => r.id), ['b', 'a']);
  });

  test('namuna boshqa tumanda — masofa ko\'rsatilmaydi; yaqinda — ko\'rsatiladi', () {
    final far = _r('far', 41.84, 60.39, demo: true);
    final near = _r('near', 39.66, 66.96, demo: true);
    final farReal = _r('farReal', 41.84, 60.39);
    expect(far.distanceKmFrom(uLat, uLng), isNull);
    expect(near.distanceKmFrom(uLat, uLng), isNotNull);
    expect(farReal.distanceKmFrom(uLat, uLng), greaterThan(500)); // ҳақиқий — ўзгармаган
  });

  test('RESTAURANT_DEMO xato kaliti 3 tilda mavjud', () {
    expect(restaurantsErrorKey('RESTAURANT_DEMO'), 'restaurants_err_RESTAURANT_DEMO');
  });
}
