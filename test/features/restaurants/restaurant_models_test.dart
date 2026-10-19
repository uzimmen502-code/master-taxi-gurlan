import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/models/order_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Restaurant.fromMap', () {
    test('to\'liq hujjat — maydonlar va ichki tuzilmalar', () {
      final r = Restaurant.fromMap('r1', {
        'name': 'Gurlan osh',
        'status': 'approved',
        'legalType': 'yatt',
        'lat': 41.84,
        'lng': 60.39,
        'prepTimeMin': 25,
        'minOrderAmount': 30000,
        'cuisineTags': ['Milliy', 7, 'Fastfud'],
        'delivery': {
          'mode': 'ava_courier',
          'pickup': true,
          'ownFee': {'type': 'distance', 'base': 4000, 'perKm': 1000, 'freeAbove': 100000, 'maxKm': 5},
        },
        'payment': {'prepay': true, 'cash': false},
        'openingHours': {'open': '09:00', 'close': '22:00'},
        'ratingAvg': 4.5,
        'ratingCount': 12,
      });
      expect(r.isApproved, isTrue);
      expect(r.isHomeCook, isFalse);
      expect(r.cuisineTags, ['Milliy', 'Fastfud'], reason: 'satr bo\'lmagan element tashlanadi');
      expect(r.delivery.isAvaCourier, isTrue);
      expect(r.delivery.pickup, isTrue);
      expect(r.delivery.ownFee.feeFor(distanceMeters: 3000, itemsTotal: 20000), 6000);
      expect(r.delivery.ownFee.feeFor(distanceMeters: 3000, itemsTotal: 100000), 0);
      expect(r.delivery.ownFee.feeFor(distanceMeters: 6000, itemsTotal: 1), isNull);
      expect(r.payment.cash, isFalse);
      expect(r.openingHours!.label, '09:00–22:00');
      expect(r.ratingAvg, 4.5);
    });

    test('bo\'sh hujjat — xavfsiz standartlar', () {
      final r = Restaurant.fromMap('x', const {});
      expect(r.name, '');
      expect(r.isApproved, isFalse);
      expect(r.isHomeCook, isTrue);
      expect(r.delivery.hasDelivery, isFalse);
      expect(r.delivery.pickup, isFalse);
      expect(r.payment.prepay, isTrue);
      expect(r.openingHours, isNull);
      expect(r.isOpenNow, isTrue, reason: 'ish vaqti yo\'q → doim ochiq');
      expect(r.distanceKmFrom(41.8, 60.3), isNull);
    });

    test('maxQtyPerItem (D-REST-26): yo\'q → 50; 1…500 butun qabul; buzilgan qiymat → default (server intOr bilan bir xil)', () {
      int q(Object? v) => Restaurant.fromMap('q', {'maxQtyPerItem': v}).maxQtyPerItem;
      expect(Restaurant.fromMap('q', const {}).maxQtyPerItem, Restaurant.defaultMaxQtyPerItem);
      expect(Restaurant.defaultMaxQtyPerItem, 50);
      expect(q(1), 1, reason: 'quyi chegara');
      expect(q(100), 100);
      expect(q(100.0), 100, reason: 'web: butun son double bo\'lib kelishi mumkin');
      expect(q(500), 500, reason: 'yuqori chegara');
      expect(q(0), 50);
      expect(q(501), 50);
      expect(q(-3), 50);
      expect(q(100.5), 50, reason: 'kasr — serverda ham default');
      expect(q('100'), 50, reason: 'satr');
      expect(q(null), 50);
    });

    test('ish vaqti: oddiy va yarim tundan o\'tadigan oraliq; pauza', () {
      final day = Restaurant.fromMap('a', {'openingHours': {'open': '09:00', 'close': '22:00'}});
      expect(day.isOpenAt(DateTime(2026, 10, 8, 12)), isTrue);
      expect(day.isOpenAt(DateTime(2026, 10, 8, 23)), isFalse);
      final night = Restaurant.fromMap('b', {'openingHours': {'open': '20:00', 'close': '02:00'}});
      expect(night.isOpenAt(DateTime(2026, 10, 8, 1)), isTrue);
      expect(night.isOpenAt(DateTime(2026, 10, 8, 15)), isFalse);
      final paused = Restaurant(id: 'p', name: 'P', pausedUntil: DateTime(2030));
      expect(paused.isOpenAt(DateTime(2026, 10, 8, 12)), isFalse);
      expect(Restaurant(id: 'q', name: 'Q', pausedUntil: DateTime(2020)).isOpenAt(DateTime(2026)), isTrue);
    });

    test('masofa — haversine (Gurlan → ~2 km shimol)', () {
      final r = Restaurant(id: 'r', name: 'R', lat: 41.8406, lng: 60.3917);
      final km = r.distanceKmFrom(41.8586, 60.3917)!;
      expect(km, closeTo(2.0, 0.05));
    });
  });

  group('MenuItem', () {
    test('available va stopUntil', () {
      final now = DateTime(2026, 10, 8, 12);
      expect(MenuItem.fromMap('a', {'name': 'A', 'price': 1000}).isAvailableAt(now), isTrue);
      expect(MenuItem.fromMap('b', {'name': 'B', 'price': 1000, 'available': false}).isAvailableAt(now), isFalse);
      final stopped = MenuItem(id: 'c', name: 'C', price: 1000, stopUntil: DateTime(2026, 10, 8, 18));
      expect(stopped.isAvailableAt(now), isFalse);
      expect(stopped.isAvailableAt(DateTime(2026, 10, 8, 19)), isTrue);
    });
  });

  group('RestaurantOrderStatus', () {
    test('bosqich indekslari va yakuniy holatlar', () {
      expect(RestaurantOrderStatus.stepIndex('placed'), 0);
      expect(RestaurantOrderStatus.stepIndex('delivered'), 5);
      expect(RestaurantOrderStatus.stepIndex('rejected'), -1);
      expect(RestaurantOrderStatus.isTerminal('delivered'), isTrue);
      expect(RestaurantOrderStatus.isFailed('delivered'), isFalse);
      expect(RestaurantOrderStatus.isFailed('delivery_failed'), isTrue);
      expect(RestaurantOrderStatus.labelKey('ready'), 'restaurants_status_ready');
      expect(restaurantsErrorKey('RESTAURANT_PAUSED'), 'restaurants_err_RESTAURANT_PAUSED');
      expect(restaurantsErrorKey(''), 'restaurants_err_generic');
    });
  });

  group('OrderModel — restoran maydonlari', () {
    test('restoran buyurtmasi: canCustomerCancel faqat placed', () {
      OrderModel o(String rs) => OrderModel(
            id: 'o',
            type: 'restaurant',
            total: 1,
            status: 'new',
            items: const [],
            restaurantStatus: rs,
          );
      expect(o('placed').isRestaurant, isTrue);
      expect(o('placed').canCustomerCancel, isTrue);
      expect(o('accepted').canCustomerCancel, isFalse);
      expect(o('ready').canCustomerCancel, isFalse);
    });

    test('non buyurtmasi eski qoidada qoladi', () {
      const o = OrderModel(id: 'o', type: 'bread', total: 1, status: 'accepted', items: []);
      expect(o.isRestaurant, isFalse);
      expect(o.canCustomerCancel, isTrue);
    });
  });
}
