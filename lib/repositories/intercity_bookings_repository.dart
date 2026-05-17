import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/formatters.dart';
import '../models/driver_client_stats.dart';
import '../models/intercity_booking.dart';

/// Қайтариладиган специфик хатолар — UI улар орқали аниқ snackbar кўрсатади.
class IntercityBookingException implements Exception {
  const IntercityBookingException(this.kind, this.message);

  final IntercityBookingErrorKind kind;
  final String message;

  @override
  String toString() => 'IntercityBookingException($kind, $message)';
}

enum IntercityBookingErrorKind {
  notEnoughSeats,
  driverInactive,
  alreadyBooked,
  unknown,
}

/// Шаҳарлараро бронлар билан ишлайдиган репозиторий.
///
/// Жорий вазифалар:
///   - **Ишончли бронь яратиш** (`createBooking`) — Firestore transaction:
///     1. ҳайдовчининг бўш ўринлари камайтирилади (агар реал ҳужжат бўлса)
///     2. `intercity_bookings/{id}` ҳужжати яратилади
///     3. `intercity_drivers/{driverId}/clients/{userPhone}` aggregation
///        increment qilinadi
///     4. `notifications` ёзилади — ҳайдовчи телефонига push (FCMService listener)
///   - **Доимий мижоз ҳолатини текшириш** (`getDriverClient`)
///   - **Мижознинг охирги бронлари** (`watchByUser`)
///   - **Бронни бекор қилиш** (`cancelBooking`) — seat реверт + counters decrement
class IntercityBookingsRepository {
  IntercityBookingsRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _bookings =>
      _db.collection('intercity_bookings');

  CollectionReference<Map<String, dynamic>> get _drivers =>
      _db.collection('intercity_drivers');

  CollectionReference<Map<String, dynamic>> _driverClients(String driverId) =>
      _drivers.doc(driverId).collection('clients');

  // ─── Доимий мижоз ҳолати ─────────────────────────────────────────────

  /// `intercity_drivers/{driverId}/clients/{userPhone}` ҳужжати —
  /// бўлмаса `null`.
  Future<DriverClientStats?> getDriverClient({
    required String driverId,
    required String userPhone,
  }) async {
    if (driverId.isEmpty || userPhone.isEmpty) return null;
    try {
      final key = phoneDigits(userPhone);
      if (key.isEmpty) return null;
      final snap = await _driverClients(driverId).doc(key).get();
      if (!snap.exists) return null;
      return DriverClientStats.fromDoc(snap);
    } catch (_) {
      return null;
    }
  }

  // ─── Мижознинг бронлари ─────────────────────────────────────────────

  /// Бир неча телефон форматида ёзилган бўлиши мумкин — barchasini qamrab
  /// olamiz. `whereIn`'da 10 элементгача рухсат.
  Stream<List<IntercityBooking>> watchByUser(
    String userPhone, {
    int limit = 10,
  }) {
    final aliases = phoneAliases(userPhone);
    if (aliases.isEmpty) return Stream.value(const []);
    return _bookings
        .where('userPhone', whereIn: aliases)
        .snapshots()
        .map((q) {
      final list = q.docs.map(IntercityBooking.fromDoc).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (list.length > limit) return list.sublist(0, limit);
      return list;
    });
  }

  /// Bir martalik қидирув — UI старт пайтида тарихни тез олиш учун.
  Future<List<IntercityBooking>> recentByUser(
    String userPhone, {
    int limit = 10,
  }) async {
    final aliases = phoneAliases(userPhone);
    if (aliases.isEmpty) return const [];
    try {
      final snap = await _bookings
          .where('userPhone', whereIn: aliases)
          .get();
      final list = snap.docs.map(IntercityBooking.fromDoc).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (list.length > limit) return list.sublist(0, limit);
      return list;
    } catch (_) {
      return const [];
    }
  }

  // ─── Ишончли бронь яратиш ────────────────────────────────────────────

  /// Транзакция ичида:
  ///   1. Driver ҳужжати ўқилади. Агар мавжуд бўлса:
  ///      - `isActive == false` → `driverInactive`
  ///      - `seats < passengers` → `notEnoughSeats`
  ///      - `seats` майдони `passengers`га камайтирилади
  ///     Агар мавжуд бўлмаса (demo ride) — seat reservation o'tkazib yuboriladi,
  ///     лекин бошқа ҳамма нарса — booking, client aggregation, notification —
  ///     одатдагидек бажарилади.
  ///   2. `intercity_bookings/{id}` яратилади (auto-id).
  ///   3. `intercity_drivers/{driverId}/clients/{userPhone}` aggregation
  ///      counters ошади (atomic increment).
  ///   4. `notifications` коллекциясига xabar ёзилади.
  ///
  /// Қайтиш қиймати — янги бронь объекти (айнан жорий ҳолат билан).
  Future<IntercityBooking> createBooking({
    required String driverId,
    required String driverPhone,
    required String driverName,
    required String carNumber,
    required String userPhone,
    required String userName,
    required String fromCity,
    required String toCity,
    required String district,
    required int passengers,
    required int pricePerSeat,
    required DateTime departureTime,
  }) async {
    if (passengers < 1) {
      throw const IntercityBookingException(
          IntercityBookingErrorKind.unknown, 'Йўловчилар сони нотўғри');
    }

    final userKey = phoneDigits(userPhone);
    if (userKey.isEmpty) {
      throw const IntercityBookingException(
          IntercityBookingErrorKind.unknown,
          'Телефон рақамингиз профилда сақланган эмас');
    }

    final totalAmount = passengers * pricePerSeat;
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(minutes: 30));
    // Hozircha intercity haydovchi-paneli yo'q. Bronni darhol "confirmed"
    // holatiga o'tkazamiz, lekin status machine kelajakda haydovchi paneli
    // qo'shilganda qaytadan "pending"'dan boshlanadi.
    const initialStatus = IntercityBookingStatus.confirmed;

    final bookingRef = _bookings.doc();
    final driverRef = _drivers.doc(driverId);
    final clientRef = _driverClients(driverId).doc(userKey);
    final notifRef = _db.collection('notifications').doc();

    try {
      await _db.runTransaction((tx) async {
        // Барча `tx.get`'ларни биринчи галда чақириш керак — Firestore талаби.
        final driverSnap = await tx.get(driverRef);
        final clientSnap = await tx.get(clientRef);

        // 1. Driver ҳужжатини текширамиз (мавжуд бўлса)
        if (driverSnap.exists) {
          final data = driverSnap.data() ?? const <String, dynamic>{};
          final isActive = (data['isActive'] as bool?) ?? true;
          if (!isActive) {
            throw const IntercityBookingException(
                IntercityBookingErrorKind.driverInactive,
                'Ҳайдовчи ҳозир бўш эмас');
          }
          final seats = (data['seats'] as num?)?.toInt() ?? 0;
          if (seats < passengers) {
            throw const IntercityBookingException(
                IntercityBookingErrorKind.notEnoughSeats,
                'Бўш ўринлар етарли эмас');
          }
          tx.update(driverRef, {
            'seats': seats - passengers,
            'lastBookedAt': FieldValue.serverTimestamp(),
          });
        }

        // 2. Booking ҳужжати
        tx.set(bookingRef, {
          'userPhone': userPhone,
          'userName': userName,
          'driverId': driverId,
          'driverPhone': driverPhone,
          'driverName': driverName,
          'carNumber': carNumber,
          'fromCity': fromCity,
          'toCity': toCity,
          'district': district,
          'passengers': passengers,
          'pricePerSeat': pricePerSeat,
          'totalAmount': totalAmount,
          'status': initialStatus,
          'createdAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromDate(expiresAt),
          'departureTime': Timestamp.fromDate(departureTime),
          'confirmedAt': FieldValue.serverTimestamp(),
        });

        // 3. Доимий мижоз aggregation. `firstBookingAt` фақат биринчи бронда
        //    ёзилади — keyingi bronlar fақат `lastBookingAt`ни yangilaydi.
        final clientPatch = <String, Object?>{
          'userName': userName,
          'userPhoneRaw': userPhone,
          'bookingCount': FieldValue.increment(1),
          'totalSpent': FieldValue.increment(totalAmount),
          'lastBookingAt': FieldValue.serverTimestamp(),
          'lastBookingId': bookingRef.id,
        };
        if (!clientSnap.exists) {
          clientPatch['firstBookingAt'] = FieldValue.serverTimestamp();
          clientPatch['completedCount'] = 0;
        }
        tx.set(clientRef, clientPatch, SetOptions(merge: true));

        // 4. Ҳайдовчига push (FCMService `notifications` коллекциясини кузатади)
        if (driverPhone.isNotEmpty) {
          final routeText = district.isNotEmpty
              ? '$fromCity → $toCity • $district'
              : '$fromCity → $toCity';
          tx.set(notifRef, {
            'targetPhone': driverPhone,
            'title': '🚗 Янги бронь!',
            'body':
                '$userName: $routeText, $passengers ўрин, ${formatPrice(totalAmount)} сўм',
            'sent': false,
            'type': 'intercity_booking',
            'bookingId': bookingRef.id,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } on IntercityBookingException {
      rethrow;
    } catch (e) {
      throw IntercityBookingException(
          IntercityBookingErrorKind.unknown, 'Бронлашда хатолик: $e');
    }

    return IntercityBooking(
      id: bookingRef.id,
      userPhone: userPhone,
      userName: userName,
      driverId: driverId,
      driverPhone: driverPhone,
      driverName: driverName,
      carNumber: carNumber,
      fromCity: fromCity,
      toCity: toCity,
      district: district,
      passengers: passengers,
      pricePerSeat: pricePerSeat,
      totalAmount: totalAmount,
      status: initialStatus,
      createdAt: now,
      expiresAt: expiresAt,
      departureTime: departureTime,
      confirmedAt: now,
    );
  }

  // ─── Бронни бекор қилиш ──────────────────────────────────────────────

  /// Мижоз ёки ҳайдовчи бекор қилади.
  ///
  /// Транзакция:
  ///   1. Бронь `active` эмас бўлса — silently skip.
  ///   2. Booking → `status: cancelled`, `cancelReason`, `cancelledAt`.
  ///   3. Driver ҳужжатида `seats` ни passengers ҳажмида orqaga қайтарамиз.
  ///   4. Client aggregation: `bookingCount` ва `totalSpent` decrement.
  Future<void> cancelBooking({
    required String bookingId,
    String? reason,
  }) async {
    final bookingRef = _bookings.doc(bookingId);

    try {
      // Аввал booking ҳужжатини олиб, ҳамма ref'ларни тайёрлаб қўямиз —
      // транзакция ичида ҳамма `tx.get`'лар `tx.update`'лардан олдин бўлиши керак.
      final pre = await bookingRef.get();
      if (!pre.exists) return;
      final b = IntercityBooking.fromDoc(pre);
      if (!b.isActive) return;

      final driverRef = _drivers.doc(b.driverId);
      final userKey = phoneDigits(b.userPhone);
      final clientRef = userKey.isNotEmpty
          ? _driverClients(b.driverId).doc(userKey)
          : null;

      await _db.runTransaction((tx) async {
        // 1. READS — барча
        final bookingSnap = await tx.get(bookingRef);
        if (!bookingSnap.exists) return;
        final fresh = IntercityBooking.fromDoc(bookingSnap);
        if (!fresh.isActive) return;

        final driverSnap = await tx.get(driverRef);
        final clientSnap =
            clientRef != null ? await tx.get(clientRef) : null;

        // 2. WRITES
        if (driverSnap.exists) {
          final seats =
              (driverSnap.data()?['seats'] as num?)?.toInt() ?? 0;
          tx.update(driverRef, {
            'seats': seats + fresh.passengers,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        tx.update(bookingRef, {
          'status': IntercityBookingStatus.cancelled,
          'cancelReason': reason ?? '',
          'cancelledAt': FieldValue.serverTimestamp(),
        });

        if (clientRef != null && clientSnap != null && clientSnap.exists) {
          tx.update(clientRef, {
            'bookingCount': FieldValue.increment(-1),
            'totalSpent': FieldValue.increment(-fresh.totalAmount),
            'lastBookingAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (e) {
      throw IntercityBookingException(
          IntercityBookingErrorKind.unknown, 'Бекор қилишда хато: $e');
    }
  }
}
