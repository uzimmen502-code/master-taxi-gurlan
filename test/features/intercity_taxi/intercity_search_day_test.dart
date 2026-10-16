import 'package:ava_gurlan/features/intercity_taxi/passenger/controllers/intercity_taxi_controller.dart';
import 'package:ava_gurlan/models/intercity_ride.dart';
import 'package:ava_gurlan/repositories/intercity_bookings_repository.dart';
import 'package:ava_gurlan/repositories/intercity_rides_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// 3б-босқич: йўловчи «Бугун / Эртага»дан ташқари ихтиёрий кунни (30 кунгача)
/// қидиради; сўров шу кун бўйича.
class _FakeRides implements IntercityRidesRepository {
  DateTime? lastBase;

  @override
  Stream<List<IntercityRide>> watchActiveRides({
    required String fromCity,
    required String toCity,
    String? passengerFromRaw,
    String? passengerToRaw,
    required String district,
    required DateTime baseDate,
  }) {
    lastBase = baseDate;
    return Stream.value(const <IntercityRide>[]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBookings implements IntercityBookingsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _FakeRides rides;
  late IntercityTaxiController c;

  setUp(() {
    rides = _FakeRides();
    c = IntercityTaxiController(ridesRepo: rides, bookingsRepo: _FakeBookings());
    c.selectFrom('Гурлан');
    c.selectTo('Тошкент');
  });

  tearDown(() => c.dispose());

  test('бошланғич — бугун', () {
    expect(c.dayOffset, 0);
    expect(c.isToday, isTrue);
    expect(c.isTomorrow, isFalse);
  });

  test('setIsToday(false) — эртага (эски тугма)', () {
    c.setIsToday(false);
    expect(c.dayOffset, 1);
    expect(c.isTomorrow, isTrue);
    c.setIsToday(true);
    expect(c.dayOffset, 0);
  });

  test('чегара: 30 кун рухсат, 31 → 30; ўтган кун → бугун', () {
    c.setDayOffset(IntercityTaxiController.maxDayOffset);
    expect(c.dayOffset, 30);
    c.setDayOffset(31);
    expect(c.dayOffset, 30);
    c.setDayOffset(-3);
    expect(c.dayOffset, 0);
  });

  test('календар куни → offset (ой алмашувида ҳам)', () {
    final now = DateTime(2026, 10, 30, 23, 50);
    c.setSearchDay(DateTime(2026, 11, 4), now);
    expect(c.dayOffset, 5);
    expect(c.searchDay(now), DateTime(2026, 11, 4));
  });

  test('қидирув танланган кун бўйича; бўш натижа — кунга мос хабар', () async {
    c.setDayOffset(5);
    await c.search();
    await pumpEventQueue();
    final now = DateTime.now();
    final want = DateTime(now.year, now.month, now.day + 5);
    final base = rides.lastBase!;
    expect(DateTime(base.year, base.month, base.day), want);
    expect(c.emptyStateKey, 'no_driver_on_date');
  });

  test('бўш натижа хабари: бугун / эртага', () async {
    await c.search();
    await pumpEventQueue();
    expect(c.emptyStateKey, 'no_driver_today');
    c.setIsToday(false);
    await c.search();
    await pumpEventQueue();
    expect(c.emptyStateKey, 'no_driver_tomorrow');
  });
}
