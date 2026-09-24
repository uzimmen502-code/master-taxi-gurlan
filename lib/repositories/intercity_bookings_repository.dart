import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../core/l10n/offline_l10n.dart';
import '../core/utils/formatters.dart';
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
  driverNotFound,
  alreadyBooked,
  alreadyActive,
  permissionDenied,
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
///   - **Мижознинг охирги бронлари** (`watchByUser`)
///   - **Бронни бекор қилиш** (`cancelBooking`) — seat реверт + counters decrement
class IntercityBookingsRepository {
  IntercityBookingsRepository({FirebaseFirestore? db, FirebaseFunctions? functions})
      : _db = db ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _bookings =>
      _db.collection('intercity_bookings');

  CollectionReference<Map<String, dynamic>> get _drivers =>
      _db.collection('intercity_drivers');

  /// CF хатосини UI тушунадиган [IntercityBookingErrorKind]га айлантиради.
  static IntercityBookingException _mapFunctionsError(
      FirebaseFunctionsException e) {
    final detail = (e.message ?? '').trim();
    switch (detail) {
      case 'not_enough_seats':
        return const IntercityBookingException(
            IntercityBookingErrorKind.notEnoughSeats, 'Бўш ўринлар етарли эмас');
      case 'driver_inactive':
        return const IntercityBookingException(
            IntercityBookingErrorKind.driverInactive, 'Бу рейс энди қабул қилмайди');
      case 'driver_not_found':
        return const IntercityBookingException(
            IntercityBookingErrorKind.driverNotFound, 'Ҳайдовчи профили топилмади');
      case 'already_booked_driver':
        return const IntercityBookingException(
            IntercityBookingErrorKind.alreadyBooked,
            'Сизда бу ҳайдовчига актив брон мавжуд');
      case 'already_active':
        return const IntercityBookingException(
            IntercityBookingErrorKind.alreadyActive, 'Сизда актив брон мавжуд');
      case 'phone_required':
        return const IntercityBookingException(
            IntercityBookingErrorKind.unknown,
            'Телефон рақамингиз профилда сақланган эмас');
    }
    if (e.code == 'permission-denied' || e.code == 'unauthenticated') {
      return const IntercityBookingException(
        IntercityBookingErrorKind.permissionDenied,
        'booking_permission_denied',
      );
    }
    return IntercityBookingException(
        IntercityBookingErrorKind.unknown, 'Бронлашда хатолик: $detail');
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

  Future<IntercityBooking?> findActiveBookingForUser(
    String userPhone,
  ) async {
    final canonical = canonicalPhoneId(userPhone);
    if (canonical.isEmpty) return null;
    try {
      final snap = await _bookings
          .where('userPhone', isEqualTo: canonical)
          .where('status', whereIn: [
            IntercityBookingStatus.pending,
            IntercityBookingStatus.confirmed,
          ])
          .limit(5)
          .get();
      if (snap.docs.isEmpty) return null;
      final bookings = snap.docs.map(IntercityBooking.fromDoc).toList();
      bookings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return bookings.first;
    } catch (e) {
      debugPrint('findActiveBookingForUser error: $e');
      return null;
    }
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

  /// Сафар киноси — фақат ўз брони (confirmed/completed) бўлган йўловчи.
  Future<bool> userHasEntertainmentAccess({
    required String userPhone,
    required String driverId,
    String? bookingId,
  }) async {
    if (userPhone.trim().isEmpty || driverId.isEmpty) return false;

    bool statusOk(String status) =>
        status == IntercityBookingStatus.confirmed ||
        status == IntercityBookingStatus.completed;

    if (bookingId != null && bookingId.isNotEmpty) {
      try {
        final snap = await _bookings.doc(bookingId).get();
        if (!snap.exists) return false;
        final b = IntercityBooking.fromDoc(snap);
        if (!phonesMatch(b.userPhone, userPhone)) return false;
        if (b.driverId != driverId) return false;
        return statusOk(b.status);
      } catch (_) {
        return false;
      }
    }

    final list = await recentByUser(userPhone, limit: 20);
    return list.any(
      (b) => b.driverId == driverId && statusOk(b.status),
    );
  }

  // ─── Ишончли бронь яратиш ────────────────────────────────────────────

  /// Бронь яратиш — 2026-09-24 дан бошлаб **тўлиқ серверда**
  /// (`intercityCreateBooking` callable, Admin SDK). Илгари бу клиент
  /// транзакцияси эди, шунинг учун `intercity_drivers.seats` клиентга очиқ
  /// бўлиши керак эди — бу эса исталган клиентга исталган ҳайдовчининг
  /// ўринларини ёзиш имконини берарди (QA топилмаси #1). Энди Firestore
  /// Rules клиентга ҳам `seats` патчини, ҳам бронь `create`ни блоклайди.
  ///
  /// Сервер бажаради: ҳайдовчини ўқиш ва валидация (isActive, seats),
  /// seat камайтириш, бронь яратиш (status'ни **сервер** `autoAcceptBookings`
  /// бўйича белгилайди — клиент ўзини `confirmed` қила олмайди, топилма #2),
  /// қулфлар, мижоз aggregation ва хабарномалар.
  ///
  /// Қайтиш қиймати — янги бронь объекти (сервердан келган id/status билан).
  Future<IntercityBooking> createBooking({
    required String driverId,
    required String driverPhone,
    required String driverName,
    required String carNumber,
    required String userPhone,
    required String userName,
    required String userGender,
    required String userBirthDate,
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

    final userKey = canonicalPhoneId(userPhone);
    if (userKey.isEmpty || phoneDigits(userKey).length < 9) {
      throw const IntercityBookingException(
          IntercityBookingErrorKind.unknown,
          'Телефон рақамингиз профилда сақланган эмас');
    }

    final totalAmount = passengers * pricePerSeat;
    if (totalAmount <= 0) {
      throw const IntercityBookingException(
        IntercityBookingErrorKind.unknown,
        'ride_not_accepting',
      );
    }

    final now = DateTime.now();
    final expiresAt = now.add(const Duration(minutes: 30));

    try {
      final res = await _functions
          .httpsCallable('intercityCreateBooking')
          .call<Map<String, dynamic>>({
        'driverId': driverId,
        'passengers': passengers,
        'pricePerSeat': pricePerSeat,
        'userName': userName,
        'userGender': userGender,
        'userBirthDate': userBirthDate,
        'fromCity': fromCity,
        'toCity': toCity,
        'district': district,
        'departureTimeMs': departureTime.millisecondsSinceEpoch,
        // Такрор босиш/тармоқ retry'ида дубль бронь бўлмаслиги учун.
        'idempotencyKey':
            '${userKey}_${driverId}_${now.millisecondsSinceEpoch ~/ 1000}',
      });

      final data = Map<String, dynamic>.from(res.data);
      final bookingId = (data['bookingId'] as String?) ?? '';
      final status =
          (data['status'] as String?) ?? IntercityBookingStatus.pending;
      if (bookingId.isEmpty) {
        throw const IntercityBookingException(
            IntercityBookingErrorKind.unknown, 'Бронлашда хатолик');
      }

      return IntercityBooking(
        id: bookingId,
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
        status: status,
        createdAt: now,
        expiresAt: expiresAt,
        departureTime: departureTime,
        userGender: userGender,
        userBirthDate: userBirthDate,
        confirmedAt:
            status == IntercityBookingStatus.confirmed ? now : null,
      );
    } on FirebaseFunctionsException catch (e) {
      throw _mapFunctionsError(e);
    } on IntercityBookingException {
      rethrow;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('permission-denied')) {
        throw const IntercityBookingException(
          IntercityBookingErrorKind.permissionDenied,
          'booking_permission_denied',
        );
      }
      throw IntercityBookingException(
          IntercityBookingErrorKind.unknown, 'Бронлашда хатолик: $e');
    }
  }

  // ─── Ҳайдовчи бронлари ───────────────────────────────────────────────

  Stream<List<IntercityBooking>> watchByDriver(
    String driverId, {
    bool includeArchived = false,
  }) {
    if (driverId.isEmpty) return Stream.value(const []);
    return _bookings
        .where('driverId', isEqualTo: driverId)
        .snapshots()
        .map((q) {
      var list = q.docs.map(IntercityBooking.fromDoc).toList();
      if (!includeArchived) {
        list = list.where((b) => !b.archivedByDriver).toList();
      }
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Stream<List<IntercityBooking>> watchPendingByDriver(String driverId) {
    if (driverId.isEmpty) return Stream.value(const []);
    return _bookings
        .where('driverId', isEqualTo: driverId)
        .where('status', isEqualTo: IntercityBookingStatus.pending)
        .snapshots()
        .map((q) {
      final list = q.docs.map(IntercityBooking.fromDoc).toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    });
  }

  Future<void> acceptBooking({
    required String bookingId,
    required String driverId,
  }) async {
    final ref = _bookings.doc(bookingId);
    IntercityBooking? accepted;

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final b = IntercityBooking.fromDoc(snap);
      if (b.driverId != driverId ||
          b.status != IntercityBookingStatus.pending) {
        return;
      }
      tx.update(ref, {
        'status': IntercityBookingStatus.confirmed,
        'confirmedAt': FieldValue.serverTimestamp(),
      });
      accepted = b;
    });

    final b = accepted;
    if (b == null || b.userPhone.isEmpty) return;
    final pickupTitle = await OfflineL10n.tr('pickup_accepted_title');
    final pickupBody = await OfflineL10n.tr('intercity_pickup_request_body');
    await _writePassengerNotification(
      userPhone: b.userPhone,
      title: pickupTitle,
      body: pickupBody,
      type: 'intercity_pickup_request',
      bookingId: bookingId,
    );
  }

  Future<void> rejectBooking({
    required String bookingId,
    required String driverId,
    String? reason,
  }) async {
    final snap = await _bookings.doc(bookingId).get();
    if (!snap.exists) return;
    if (IntercityBooking.fromDoc(snap).driverId != driverId) return;
    await cancelBooking(
      bookingId: bookingId,
      reason: reason ?? 'Ҳайдовчи рад этди',
    );
  }

  /// Сафарни якунлаш — серверда (`intercityCompleteBooking`): статус,
  /// seat қайтариш (seatCapacity билан чекланган) ва йўловчига хабар.
  /// Seat мутацияси клиентда қолдирилмади — қаранг [createBooking] изоҳи.
  Future<void> completeBooking({
    required String bookingId,
    required String driverId,
  }) async {
    try {
      await _functions
          .httpsCallable('intercityCompleteBooking')
          .call<Map<String, dynamic>>({'bookingId': bookingId});
    } on FirebaseFunctionsException catch (e) {
      throw _mapFunctionsError(e);
    }
  }

  Future<void> markPickedUp(String bookingId) async {
    await _bookings.doc(bookingId).update({
      'pickedUp': true,
      'pickedUpAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setArchived({
    required String bookingId,
    required bool archived,
  }) async {
    await _bookings.doc(bookingId).update({
      'archivedByDriver': archived,
    });
  }

  Future<void> updatePickup({
    required String bookingId,
    required String userPhone,
    String? address,
    double? lat,
    double? lng,
  }) async {
    final ref = _bookings.doc(bookingId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final b = IntercityBooking.fromDoc(snap);
    if (canonicalPhoneId(b.userPhone) != canonicalPhoneId(userPhone)) return;
    await ref.update({
      if (address != null) 'pickupAddress': address.trim(),
      if (lat != null) 'pickupLat': lat,
      if (lng != null) 'pickupLng': lng,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> getDriverAutoAccept(String driverId) async {
    if (driverId.isEmpty) return false;
    final snap = await _drivers.doc(driverId).get();
    return (snap.data()?['autoAcceptBookings'] as bool?) ?? false;
  }

  Future<void> setDriverAutoAccept(String driverId, bool value) async {
    if (driverId.isEmpty) return;
    final ref = _drivers.doc(driverId);
    final data = {
      'autoAcceptBookings': value,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final snap = await ref.get();
    if (snap.exists) {
      await ref.update(data);
    } else {
      await ref.set(data, SetOptions(merge: true));
    }
  }

  // ─── Бронни бекор қилиш ──────────────────────────────────────────────

  /// Ҳайдовчи рейсни ёпганда ёки янги рейс очганда — барча pending/confirmed бронлар.
  Future<int> cancelActiveBookingsForDriver(
    String driverId, {
    String reason = 'Ҳайдовчи рейсни бекор қилди',
  }) async {
    if (driverId.isEmpty) return 0;
    try {
      final snap = await _bookings
          .where('driverId', isEqualTo: driverId)
          .where('status', whereIn: [
            IntercityBookingStatus.pending,
            IntercityBookingStatus.confirmed,
          ])
          .get();
      var count = 0;
      for (final doc in snap.docs) {
        try {
          await cancelBooking(bookingId: doc.id, reason: reason);
          count++;
        } catch (_) {}
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  /// Мижоз ёки ҳайдовчи бекор қилади.
  ///
  ///
  /// 2026-09-24: бекор қилиш ҳам **серверда** (`intercityCancelBooking`):
  /// статус, seat қайтариш (seatCapacity билан чекланган), мижоз
  /// aggregation, қулф тозалаш ва хабарномалар (йўловчига, йўловчи ўзи
  /// бекор қилса — ҳайдовчига ҳам). Рухсат серверда текширилади: фақат
  /// иштирокчи (йўловчи/ҳайдовчи) ёки админ. Қаранг [createBooking] изоҳи.
  Future<void> cancelBooking({
    required String bookingId,
    String? reason,
  }) async {
    try {
      await _functions
          .httpsCallable('intercityCancelBooking')
          .call<Map<String, dynamic>>({
        'bookingId': bookingId,
        'reason': reason ?? '',
      });
    } on FirebaseFunctionsException catch (e) {
      throw _mapFunctionsError(e);
    } catch (_) {
      throw const IntercityBookingException(
          IntercityBookingErrorKind.unknown, 'booking_cancel_failed');
    }
  }

  Future<void> _writePassengerNotification({
    required String userPhone,
    required String title,
    required String body,
    required String type,
    String? bookingId,
  }) async {
    if (userPhone.trim().isEmpty) return;
    await _db.collection('notifications').add({
      'targetPhone': notificationTargetPhone(userPhone),
      'title': title,
      'body': body,
      'sent': false,
      'type': type,
      if (bookingId != null) 'bookingId': bookingId,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
