import 'dart:async';

import 'package:ava_gurlan/features/driver_schedule/controllers/driver_schedule_controller.dart';
import 'package:ava_gurlan/repositories/marshrut_driver_repository.dart';
import 'package:ava_gurlan/repositories/schedules_repository.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Haydovchi jadvali (shaharlararo): standart vaqt o'tmishda bo'lmasin,
/// o'tgan vaqt bilan saqlab bo'lmasin, ikki marta bosish ikki reys ochmasin,
/// xatolar sodda l10n kaliti bilan (xom istisno matnisiz).
class _FakeSchedules extends Fake implements SchedulesRepository {
  final registered = <String>[];
  Object? failWith;

  @override
  Future<String> registerDriverSchedule({
    required String driverId,
    required String taxiType,
    required String driverName,
    required String driverPhone,
    required String driverCar,
    required String driverPlate,
    required String date,
    required DateTime expiresAt,
    required int seats,
    required String fromText,
    required String toText,
    List<String> stops = const [],
    String direction = '',
    String? startTime,
    String? endTime,
    int? price,
    String? billingTripId,
  }) async {
    if (failWith != null) throw failWith!;
    registered.add('$date $startTime $billingTripId');
    return 'S1';
  }
}

class _FakeMarshrut extends Fake implements MarshrutDriverRepository {}

void main() {
  late _FakeSchedules schedules;
  late DateTime now;

  DriverScheduleController make({List<String>? stops}) {
    return DriverScheduleController(
      taxiType: 'intercity',
      driverName: 'Ali',
      driverPhone: '+998901234567',
      driverCar: 'Cobalt',
      driverPlate: '01A123BC',
      schedulesRepo: schedules,
      marshrutDriverRepo: _FakeMarshrut(),
      clock: () => now,
    );
  }

  setUp(() {
    schedules = _FakeSchedules();
    now = DateTime(2026, 10, 16, 15, 2);
    SharedPreferences.setMockInitialValues({
      'user_phone': '998901234567',
      'route_from_intercity': 'Хоразм • Гурлан',
      'route_to_intercity': 'Тошкент',
      'intercity_price_intercity': '35000',
      'intercity_departure_hour': '08:00',
    });
  });

  test('init: saqlangan 08:00 (o\'tgan) -> 15:30 bugun', () async {
    final c = make();
    await c.init();
    expect(c.departureIsTomorrow, isFalse);
    expect(c.departureTime, const TimeOfDay(hour: 15, minute: 30));
  });

  test('init: prefs bo\'sh bo\'lsa ham standart o\'tmishda emas', () async {
    SharedPreferences.setMockInitialValues({'user_phone': '998901234567'});
    final c = make();
    await c.init();
    expect(c.departureTime, const TimeOfDay(hour: 15, minute: 30));
  });

  test('init: kech (23:40) -> ertaga 08:00', () async {
    now = DateTime(2026, 10, 16, 23, 40);
    final c = make();
    await c.init();
    expect(c.departureIsTomorrow, isTrue);
    expect(c.departureTime, const TimeOfDay(hour: 8, minute: 0));
  });

  test('confirm: o\'tgan vaqt bloklanadi, to\'lov oqimi chaqirilmaydi', () async {
    final c = make();
    await c.init();
    var published = 0;
    c.intercityPublisher = ({
      required farePerSeat,
      required from,
      required to,
      required scheduleDate,
      required startTime,
      required seats,
      required departureAt,
    }) async {
      published++;
      return 'T1';
    };
    c.setDepartureTime(const TimeOfDay(hour: 8, minute: 0)); // qo'lda o'tgan
    final ok = await c.confirm();
    expect(ok, isFalse);
    expect(c.errorMessage, 'ic_err_time_past');
    expect(published, 0);
    expect(c.isSaving, isFalse);
  });

  test('confirm: o\'tgan vaqt "Ertaga" tanlansa ruxsat', () async {
    final c = make();
    await c.init();
    String? gotDate;
    c.intercityPublisher = ({
      required farePerSeat,
      required from,
      required to,
      required scheduleDate,
      required startTime,
      required seats,
      required departureAt,
    }) async {
      gotDate = scheduleDate;
      return 'T1';
    };
    c.setDepartureTime(const TimeOfDay(hour: 8, minute: 0));
    c.setDepartureIsTomorrow(true);
    expect(await c.confirm(), isTrue);
    expect(gotDate, '2026-10-17');
  });

  test('ikki marta bosish: saqlash bayrog\'i birinchi await dan OLDIN', () async {
    final c = make();
    await c.init();
    final gate = Completer<String?>();
    var published = 0;
    c.intercityPublisher = ({
      required farePerSeat,
      required from,
      required to,
      required scheduleDate,
      required startTime,
      required seats,
      required departureAt,
    }) {
      published++;
      return gate.future;
    };
    final first = c.confirm();
    // Birinchi await (uid o'qish) tugamasdan bayroq allaqachon ko'tarilgan.
    expect(c.isSaving, isTrue);
    final second = await c.confirm();
    expect(second, isFalse);
    gate.complete('T1');
    expect(await first, isTrue);
    expect(published, 1);
    expect(schedules.registered, hasLength(1));
  });

  test('xato: ruxsat -> l10n kaliti, xom istisno matni yo\'q; komissiya qaytariladi',
      () async {
    final c = make();
    await c.init();
    String? refunded;
    c.intercityRefund = (id) async => refunded = id;
    c.intercityPublisher = ({
      required farePerSeat,
      required from,
      required to,
      required scheduleDate,
      required startTime,
      required seats,
      required departureAt,
    }) async =>
        'T9';
    schedules.failWith =
        Exception('[cloud_firestore/permission-denied] secret path /x');
    expect(await c.confirm(), isFalse);
    expect(c.errorMessage, 'ic_err_no_permission');
    expect(c.errorMessage!.contains('Exception'), isFalse);
    expect(refunded, 'T9');
    expect(c.isSaving, isFalse);
  });

  test('xato: noma\'lum istisno -> umumiy sodda matn', () async {
    final c = make();
    await c.init();
    c.intercityPublisher = ({
      required farePerSeat,
      required from,
      required to,
      required scheduleDate,
      required startTime,
      required seats,
      required departureAt,
    }) async =>
        'T1';
    schedules.failWith = StateError('boom internal');
    expect(await c.confirm(), isFalse);
    expect(c.errorMessage, 'taxi_publish_failed');
  });

  test('xato: ma\'qullanmagan haydovchi -> taxi_not_allowed', () async {
    final c = make();
    await c.init();
    c.intercityPublisher = ({
      required farePerSeat,
      required from,
      required to,
      required scheduleDate,
      required startTime,
      required seats,
      required departureAt,
    }) async =>
        'T1';
    schedules.failWith = const DriverScheduleApprovalException('ichki matn');
    expect(await c.confirm(), isFalse);
    expect(c.errorMessage, 'taxi_not_allowed');
  });
}
