import 'dart:async';

import 'package:ava_gurlan/features/intercity_taxi/passenger/controllers/me_and_passengers_controller.dart';
import 'package:ava_gurlan/models/intercity_booking.dart';
import 'package:ava_gurlan/repositories/intercity_bookings_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

/// Yo'lovchi paneli faqat O'Z bronini kuzatadi. Avval `where driverId == X`
/// ro'yxat so'rovi edi: rules (faqat ishtirokchi o'qiydi) uni rad etib panelni
/// yo'qotardi, ruxsat kengroq bo'lsa esa boshqa yo'lovchilar ismi/yoshi/
/// telefoni oqib chiqardi.
IntercityBooking _booking(String id, {String status = 'confirmed'}) =>
    IntercityBooking(
      id: id,
      userPhone: '998901111111',
      userName: 'Men',
      driverId: '998902222222',
      driverPhone: '998902222222',
      driverName: 'Haydovchi',
      carNumber: '01A',
      fromCity: 'Гурлан',
      toCity: 'Тошкент',
      district: '',
      passengers: 1,
      pricePerSeat: 35000,
      totalAmount: 35000,
      status: status,
      createdAt: DateTime(2026, 10, 16, 10),
      expiresAt: DateTime(2026, 10, 16, 11),
      departureTime: DateTime(2026, 10, 16, 18),
    );

/// Faqat `watchMyBooking` ni biladi: `watchByDriver` va boshqa ro'yxat
/// so'rovlari chaqirilsa `noSuchMethod` xato beradi (test yiqiladi).
class _FakeRepo implements IntercityBookingsRepository {
  final watched = <String>[];
  final ctrl = StreamController<IntercityBooking?>.broadcast();

  @override
  Stream<IntercityBooking?> watchMyBooking(String bookingId) {
    watched.add(bookingId);
    return ctrl.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ── Firestore zanjiri: faqat collection().doc().snapshots() ruxsat ──

class _Snap extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  _Snap(this.id, this._data);
  @override
  final String id;
  final Map<String, dynamic>? _data;
  @override
  bool get exists => _data != null;
  @override
  Map<String, dynamic>? data() => _data;
}

class _DocRef extends Fake implements DocumentReference<Map<String, dynamic>> {
  _DocRef(this.stream);
  final Stream<DocumentSnapshot<Map<String, dynamic>>> stream;
  @override
  Stream<DocumentSnapshot<Map<String, dynamic>>> snapshots({
    bool includeMetadataChanges = false,
    ListenSource source = ListenSource.defaultSource,
  }) =>
      stream;
}

/// `where` / `get` / `orderBy`... aniqlanmagan: ishlatilsa UnimplementedError.
class _Col extends Fake implements CollectionReference<Map<String, dynamic>> {
  _Col(this.log, this.stream);
  final List<String> log;
  final Stream<DocumentSnapshot<Map<String, dynamic>>> stream;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    log.add('doc:$path');
    return _DocRef(stream);
  }
}

class _Db extends Fake implements FirebaseFirestore {
  _Db(this.stream);
  final Stream<DocumentSnapshot<Map<String, dynamic>>> stream;
  final log = <String>[];
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) {
    log.add('collection:$path');
    return _Col(log, stream);
  }
}

class _Fns extends Fake implements FirebaseFunctions {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MeAndPassengersController', () {
    late _FakeRepo repo;
    late MeAndPassengersController c;

    setUp(() {
      repo = _FakeRepo();
      c = MeAndPassengersController(repo: repo, userPhone: '998901111111');
    });

    tearDown(() {
      c.dispose();
      repo.ctrl.close();
    });

    test('faqat O\'Z broni kuzatiladi (bron id bo\'yicha), haydovchi ro\'yxati emas',
        () async {
      c.attachWithBooking('998902222222', _booking('B1'));
      expect(repo.watched, ['B1']);
      expect(c.hasActiveBooking, isTrue);
      expect(c.myBooking!.id, 'B1');
    });

    test('bron yangilanishi paneldagi holatni almashtiradi', () async {
      c.attachWithBooking('998902222222', _booking('B1', status: 'pending'));
      repo.ctrl.add(_booking('B1', status: 'confirmed'));
      await pumpEventQueue();
      expect(c.myBooking!.status, 'confirmed');
      expect(c.hasActiveBooking, isTrue);
    });

    test('bekor qilingan bron -> panel yopiladi', () async {
      c.attachWithBooking('998902222222', _booking('B1'));
      repo.ctrl.add(_booking('B1', status: 'cancelled'));
      await pumpEventQueue();
      expect(c.hasActiveBooking, isFalse);
      expect(c.myBooking, isNull);
    });

    test('oqim xatosi faol bron panelini YO\'QOTMAYDI', () async {
      c.attachWithBooking('998902222222', _booking('B1'));
      repo.ctrl.addError(StateError('permission-denied'));
      await pumpEventQueue();
      expect(c.hasActiveBooking, isTrue);
      expect(c.myBooking!.id, 'B1');
      expect(c.isLoading, isFalse);
    });

    test('attach(driverId, bookingId) ham bron id bo\'yicha kuzatadi', () {
      c.attach('998902222222', 'B7');
      expect(repo.watched, ['B7']);
    });
  });

  group('IntercityBookingsRepository.watchMyBooking so\'rov shakli', () {
    test('faqat collection(intercity_bookings).doc(id) — where/list so\'rovi yo\'q',
        () async {
      final stream = Stream<DocumentSnapshot<Map<String, dynamic>>>.fromIterable([
        _Snap('B1', {
          'userPhone': '998901111111',
          'driverId': '998902222222',
          'status': 'confirmed',
        }),
        _Snap('B1', null), // hujjat yo'q
      ]);
      final db = _Db(stream);
      final repo = IntercityBookingsRepository(db: db, functions: _Fns());

      final out = await repo.watchMyBooking('B1').toList();
      expect(db.log, ['collection:intercity_bookings', 'doc:B1']);
      expect(out, hasLength(2));
      expect(out.first!.id, 'B1');
      expect(out.first!.status, 'confirmed');
      expect(out.last, isNull);
    });

    test('bo\'sh id -> so\'rovsiz null', () async {
      final db = _Db(const Stream.empty());
      final repo = IntercityBookingsRepository(db: db, functions: _Fns());
      expect(await repo.watchMyBooking('').toList(), [null]);
      expect(db.log, isEmpty);
    });
  });
}
