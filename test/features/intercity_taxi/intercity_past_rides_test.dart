import 'dart:async';

import 'package:ava_gurlan/features/intercity_taxi/passenger/controllers/intercity_taxi_controller.dart';
import 'package:ava_gurlan/models/intercity_ride.dart';
import 'package:ava_gurlan/repositories/intercity_bookings_repository.dart';
import 'package:ava_gurlan/repositories/intercity_rides_repository.dart';
import 'package:ava_gurlan/utils/intercity_places.dart';
import 'package:flutter_test/flutter_test.dart';

/// Yo'lovchi qidiruvi: jo'nash vaqti o'tib ketgan reyslar ro'yxatda va
/// bronda qolmaydi; bo'sh natija xato emas (alohida sabab kaliti).
class _FakeRides implements IntercityRidesRepository {
  final controller = StreamController<List<IntercityRide>>.broadcast();

  @override
  Stream<List<IntercityRide>> watchActiveRides({
    required String fromCity,
    required String toCity,
    String? passengerFromRaw,
    String? passengerToRaw,
    required String district,
    required DateTime baseDate,
  }) =>
      controller.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBookings implements IntercityBookingsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

IntercityRide _ride(String id, DateTime dep, {int seats = 3, double rating = 4}) =>
    IntercityRide(
      id: id,
      driverName: 'D$id',
      rating: rating,
      carModel: 'Cobalt',
      carNumber: '01A',
      phoneNumber: '998901234567',
      price: 35000,
      availableSeats: seats,
      fromCity: 'Гурлан',
      toCity: 'Тошкент',
      district: '',
      departureTime: dep,
    );

void main() {
  late _FakeRides repo;
  late IntercityTaxiController c;
  late DateTime now;

  setUp(() {
    repo = _FakeRides();
    now = DateTime(2026, 10, 16, 15, 2);
    c = IntercityTaxiController(
      ridesRepo: repo,
      bookingsRepo: _FakeBookings(),
      clock: () => now,
    );
    c.selectFrom('Хоразм • Гурлан');
    c.selectTo('Тошкент');
  });

  tearDown(() {
    c.dispose();
    repo.controller.close();
  });

  Future<void> emit(List<IntercityRide> list) async {
    repo.controller.add(list);
    await pumpEventQueue();
  }

  test('o\'tib ketgan reys ro\'yxatda ko\'rinmaydi (08:00 va 15:00), kelgusisi qoladi',
      () async {
    await c.search();
    await emit([
      _ride('old', DateTime(2026, 10, 16, 8, 0)),
      _ride('justGone', DateTime(2026, 10, 16, 15, 1)),
      _ride('soon', DateTime(2026, 10, 16, 15, 30)),
      _ride('evening', DateTime(2026, 10, 16, 21, 0)),
    ]);
    expect(c.rides.map((r) => r.id).toSet(), {'soon', 'evening'});
    expect(c.emptyStateKey, isNull);
  });

  test('aynan hozirgi vaqt: hali o\'tmagan (chegara)', () async {
    await c.search();
    await emit([_ride('now', DateTime(2026, 10, 16, 15, 2))]);
    expect(c.rides.map((r) => r.id), ['now']);
  });

  test('hammasi o\'tgan bo\'lsa: bo\'sh holat sababi, xato emas', () async {
    await c.search();
    await emit([_ride('old', DateTime(2026, 10, 16, 8, 0))]);
    expect(c.rides, isEmpty);
    expect(c.emptyStateKey, 'no_driver_today');
    expect(c.errorMessage, isNull);
  });

  test('ertangi kun: soat o\'tgan-o\'tmaganligi hisobga olinmaydi (kelajak)', () async {
    c.setIsToday(false);
    await c.search();
    await emit([_ride('t', DateTime(2026, 10, 17, 8, 0))]);
    expect(c.rides.map((r) => r.id), ['t']);
  });

  test('yo\'lovchi soniga o\'rin yetmasa: alohida sabab', () async {
    await c.search();
    await emit([_ride('full', DateTime(2026, 10, 16, 18, 0), seats: 0)]);
    expect(c.rides, isEmpty);
    expect(c.emptyStateKey, 'no_seats_for_passenger_count');
  });

  test('emptyStateKey: qidirish tugamaguncha va natija bor paytda null', () async {
    expect(c.emptyStateKey, isNull); // qidirilmagan
    await c.search();
    expect(c.emptyStateKey, isNull); // hali yuklanmoqda
    await emit([_ride('a', DateTime(2026, 10, 16, 18, 0))]);
    expect(c.emptyStateKey, isNull); // natija bor
  });

  test('bron: o\'tib ketgan reysga bron qilinmaydi (serverga murojaatsiz)', () async {
    final r = await c.bookRide(
      _ride('old', DateTime(2026, 10, 16, 8, 0)),
      defaultPassengerName: 'Yo\'lovchi',
    );
    expect(r.$1, isNull);
    expect(r.$2, 'intercity_ride_departed');
  });

  group('uy hududi bo\'yicha "Qaerdan?" ni to\'ldirish', () {
    String home(String region, String district) =>
        IntercityPlaces.canonicalFromRegionDistrict(
            regionLabel: region, districtLabel: district);

    test('Xorazm / Gurlan -> kanonik joy', () {
      expect(home('Хоразм', 'Гурлан'), 'Хоразм • Гурлан');
      expect(home('Хоразм вилояти', 'Гурлан'), 'Хоразм • Гурлан');
    });

    test('lotin yozuvi ham moslanadi', () {
      expect(home('Xorazm', 'Gurlan'), 'Хоразм • Гурлан');
    });

    test('qat\'iy moslik: "Қува" "Қувасой" ga adashmaydi', () {
      expect(home('Фарғона', 'Қува'), 'Фарғона • Қува');
      expect(home('Фарғона', 'Қувасой'), 'Фарғона • Қувасой');
    });

    test('shahar nomi (tumansiz ro\'yxat joyi)', () {
      expect(home('Хоразм', 'Урганч'), 'Урганч');
    });

    test('noma\'lum tuman yoki bo\'sh -> bo\'sh (oldindan to\'ldirilmaydi)', () {
      expect(home('Хоразм', 'Номаълум'), '');
      expect(home('', ''), '');
      expect(home('Хоразм', ''), '');
    });
  });
}
