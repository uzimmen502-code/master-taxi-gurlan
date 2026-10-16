// ignore_for_file: subtype_of_sealed_class
// (Firestore tiplari @sealed; testda faqat kerakli metodlari soxtalashtiriladi.)
import 'package:ava_gurlan/features/intercity_taxi/driver/controllers/intercity_driver_panel_controller.dart';
import 'package:ava_gurlan/models/intercity_booking.dart';
import 'package:ava_gurlan/repositories/intercity_bookings_repository.dart';
import 'package:ava_gurlan/repositories/intercity_rides_repository.dart';
import 'package:ava_gurlan/repositories/schedules_repository.dart';
import 'package:ava_gurlan/repositories/taxi_billing_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Reysni tugatish": TARTIB (e'lon yopiladi -> komissiya -> bronlar), har
/// bosqich xatosi yutilmaydi, safar boshlash haqiqiy natijani qaytaradi.
final log = <String>[];

class _FakeDoc extends Fake implements DocumentReference<Map<String, dynamic>> {
  _FakeDoc(this.owner);
  final _FakeDb owner;
  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    log.add('listing.set isActive=${data['isActive']}');
    if (owner.failListing) throw Exception('network down');
  }
}

class _FakeCol extends Fake implements CollectionReference<Map<String, dynamic>> {
  _FakeCol(this.owner, this.name);
  final _FakeDb owner;
  final String name;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    expect(name, 'intercity_drivers'); // faqat O'Z e'loni yoziladi
    return _FakeDoc(owner);
  }
}

class _FakeDb extends Fake implements FirebaseFirestore {
  bool failListing = false;
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _FakeCol(this, path);
}

class _FakeSchedules extends Fake implements SchedulesRepository {
  @override
  Future<bool> endTodayWork(
      {required String driverId, required String date}) async {
    log.add('schedules.end $date');
    return true;
  }
}

class _FakeBookings implements IntercityBookingsRepository {
  ({int cancelled, int failed}) result = (cancelled: 2, failed: 0);
  Object? throwOnLookup;

  @override
  Future<({int cancelled, int failed})> cancelActiveBookingsForDriverDetailed(
    String driverId, {
    String reason = '',
  }) async {
    log.add('bookings.cancel');
    if (throwOnLookup != null) throw throwOnLookup!;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBilling implements TaxiBillingRepository {
  bool fail = false;
  bool failReschedule = false;
  bool? hadAvaBooking;

  @override
  Future<Map<String, dynamic>> reschedule({
    required String tripId,
    required DateTime departureAt,
    String? scheduleDate,
    String? startTime,
    int? farePerSeat,
  }) async {
    log.add('billing.reschedule $tripId');
    if (failReschedule) {
      throw const TaxiBillingException(
          'failed-precondition', 'departure_in_past', 'x');
    }
    return {'status': 'published'};
  }

  @override
  Future<Map<String, dynamic>> cancel({
    required String tripId,
    bool hadAvaBooking = false,
    double? driverLat,
    double? driverLng,
  }) async {
    log.add('billing.cancel $tripId');
    this.hadAvaBooking = hadAvaBooking;
    if (fail) throw const TaxiBillingException('unavailable', '', 'x');
    return {'status': 'cancelled'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRides implements IntercityRidesRepository {
  bool fail = false;
  @override
  Future<void> startTrip(String driverId) async {
    if (fail) throw Exception('permission-denied');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

IntercityBooking _b(String id, String status) => IntercityBooking(
      id: id,
      userPhone: '998901111111',
      userName: 'Yo\'lovchi',
      driverId: '998902222222',
      driverPhone: '998902222222',
      driverName: 'H',
      carNumber: '01A',
      fromCity: 'a',
      toCity: 'b',
      district: '',
      passengers: 1,
      pricePerSeat: 1000,
      totalAmount: 1000,
      status: status,
      createdAt: DateTime(2026, 10, 16),
      expiresAt: DateTime(2026, 10, 16),
      departureTime: DateTime(2026, 10, 16),
    );

void main() {
  late _FakeDb db;
  late _FakeBookings bookings;
  late _FakeBilling billing;
  late _FakeRides rides;
  late IntercityDriverPanelController c;

  setUp(() {
    log.clear();
    db = _FakeDb();
    bookings = _FakeBookings();
    billing = _FakeBilling();
    rides = _FakeRides();
    c = IntercityDriverPanelController(
      driverId: '998902222222',
      driverName: 'H',
      driverPhone: '998902222222',
      driverCar: 'Cobalt',
      driverPlate: '01A',
      bookingsRepo: bookings,
      schedulesRepo: _FakeSchedules(),
      ridesRepo: rides,
      db: db,
      billingRepo: billing,
      lastKnownPosition: () async => null,
    );
    c.tripData = {
      'isActive': true,
      'billingTripId': 'T1',
      'scheduleDate': '2026-10-16',
    };
    c.bookings = [_b('B1', 'confirmed')];
  });

  tearDown(() => c.dispose());

  test('TARTIB: avval e\'lon yopiladi, keyin komissiya, eng oxirida bronlar',
      () async {
    final r = await c.endTripListing();
    expect(log, [
      'listing.set isActive=false',
      'schedules.end 2026-10-16',
      'billing.cancel T1',
      'bookings.cancel',
    ]);
    expect(r.ok, isTrue);
    expect(r.bookingsCancelled, 2);
    expect(intercityEndTripNoticeKey(r), isNull);
  });

  test('fraud signali: tasdiqlangan bron bor edi -> hadAvaBooking=true', () async {
    await c.endTripListing();
    expect(billing.hadAvaBooking, isTrue);
  });

  test('e\'lon yopilmasa: hech narsa bekor qilinmaydi, aniq xato', () async {
    db.failListing = true;
    final r = await c.endTripListing();
    expect(log, ['listing.set isActive=false']);
    expect(r.listingClosed, isFalse);
    expect(intercityEndTripNoticeKey(r), 'ic_end_failed');
    expect(c.endIncomplete, isTrue);
  });

  test('komissiya qaytmasa: bronlar baribir bekor qilinadi, xato ko\'rsatiladi',
      () async {
    billing.fail = true;
    final r = await c.endTripListing();
    expect(log.last, 'bookings.cancel');
    expect(r.refundFailed, isTrue);
    expect(r.listingClosed, isTrue);
    expect(intercityEndTripNoticeKey(r), 'ic_end_refund_failed');
    expect(c.endIncomplete, isTrue);
  });

  test('bronlar qisman bekor qilindi: yo\'qotilgan son va xabar', () async {
    bookings.result = (cancelled: 1, failed: 2);
    final r = await c.endTripListing();
    expect(r.bookingsFailed, 2);
    expect(intercityEndTripNoticeKey(r), 'ic_end_bookings_failed');
    expect(c.endIncomplete, isTrue);
  });

  test('bronlar ro\'yxati o\'qilmadi (istisno): "noma\'lum" = muvaffaqiyatsiz hisoblanadi',
      () async {
    bookings.throwOnLookup = Exception('unavailable');
    final r = await c.endTripListing();
    expect(r.bookingsFailed, greaterThan(0));
    expect(intercityEndTripNoticeKey(r), 'ic_end_bookings_failed');
  });

  test('billingTripId yo\'q (eski e\'lon): serverga komissiya so\'rovi yo\'q', () async {
    c.tripData = {'isActive': true};
    await c.endTripListing();
    expect(log.where((l) => l.startsWith('billing')), isEmpty);
    expect(log.first, 'listing.set isActive=false');
    expect(log.last, 'bookings.cancel');
  });

  test('xabar ustuvorligi: e\'lon > bronlar > komissiya', () {
    expect(
      intercityEndTripNoticeKey(const EndListingResult(
          listingClosed: false, refundFailed: true, bookingsFailed: 3)),
      'ic_end_failed',
    );
    expect(
      intercityEndTripNoticeKey(const EndListingResult(
          listingClosed: true, refundFailed: true, bookingsFailed: 3)),
      'ic_end_bookings_failed',
    );
  });

  test('qayta urinish tugmasi: e\'lon yopiq bo\'lsa ham bronlar qolsa ko\'rinadi', () async {
    bookings.result = (cancelled: 0, failed: 1);
    await c.endTripListing();
    c.tripData = {'isActive': false}; // e'lon yopildi
    expect(c.canEndTrip, isTrue); // endIncomplete / ochiq bron

    bookings.result = (cancelled: 1, failed: 0);
    final r2 = await c.endTripListing();
    expect(r2.ok, isTrue);
    c.bookings = const []; // bronlar bekor bo'ldi
    expect(c.endIncomplete, isFalse);
    expect(c.canEndTrip, isFalse);
  });

  test('reschedule: avval server, keyin faqat O\'Z e\'loni; yo\'lovchi hujjatlariga yozmaydi',
      () async {
    await c.rescheduleTrip(
      departureAt: DateTime(2026, 10, 17, 9, 0),
      scheduleDate: '2026-10-17',
      startTime: '09:00',
    );
    expect(log, ['billing.reschedule T1', 'listing.set isActive=null']);
  });

  test('reschedule: server rad etsa (departure_in_past) e\'lon o\'zgarmaydi, sabab saqlanadi',
      () async {
    billing.failReschedule = true;
    await expectLater(
      c.rescheduleTrip(
        departureAt: DateTime(2026, 10, 16, 8, 0),
        scheduleDate: '2026-10-16',
        startTime: '08:00',
      ),
      throwsA(isA<TaxiBillingException>()
          .having((e) => e.reason, 'reason', 'departure_in_past')),
    );
    expect(log, ['billing.reschedule T1']);
  });

  test('startTrip: muvaffaqiyat -> true, xato -> false (yutilmaydi)', () async {
    expect(await c.startTrip(), isTrue);
    rides.fail = true;
    expect(await c.startTrip(), isFalse);
  });
}
