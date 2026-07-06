import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/l10n/offline_l10n.dart';
import '../core/utils/formatters.dart';
import '../features/intercity_taxi/intercity_driver_alert_text.dart';
import '../models/intercity_booking.dart';
import '../utils/intercity_places.dart';

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
  IntercityBookingsRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _bookings =>
      _db.collection('intercity_bookings');

  CollectionReference<Map<String, dynamic>> get _drivers =>
      _db.collection('intercity_drivers');

  static String _bookingRouteNotice(IntercityBooking b) {
    final raw = b.driverRouteLabel.trim().isNotEmpty
        ? b.driverRouteLabel
        : b.routeShort;
    return IntercityPlaces.shortRouteLabel(raw);
  }

  CollectionReference<Map<String, dynamic>> _driverClients(String driverId) =>
      _drivers.doc(driverId).collection('clients');

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

    final bookingRef = _bookings.doc();
    final driverRef = _drivers.doc(driverId);
    final clientRef = _driverClients(driverId).doc(userKey);
    final notifRef = _db.collection('notifications').doc();
    final lockRef =
        _db.collection('intercity_booking_locks').doc('${driverId}_$userKey');
    final passengerLockRef =
        _db.collection('intercity_passenger_locks').doc(userKey);

    final driverPre = await driverRef.get();
    if (!driverPre.exists) {
      throw const IntercityBookingException(
        IntercityBookingErrorKind.driverNotFound,
        'Ҳайдовчи профили топилмади',
      );
    }
    final autoAccept =
        (driverPre.data()?['autoAcceptBookings'] as bool?) ?? false;
    final initialStatus = autoAccept
        ? IntercityBookingStatus.confirmed
        : IntercityBookingStatus.pending;

    final pickupRequestBody =
        await OfflineL10n.tr('intercity_pickup_request_body');
    final bookingConfirmedTitle =
        await OfflineL10n.tr('booking_confirmed_title');

    try {
      await _db.runTransaction((tx) async {
        // Барча `tx.get`'ларни биринчи галда чақириш керак — Firestore талаби.
        final driverSnap = await tx.get(driverRef);
        final clientSnap = await tx.get(clientRef);
        final lockSnap = await tx.get(lockRef);
        final passengerLockSnap = await tx.get(passengerLockRef);
        final driverData = driverSnap.data() ?? const <String, dynamic>{};

        if (!driverSnap.exists) {
          throw const IntercityBookingException(
            IntercityBookingErrorKind.driverNotFound,
            'Ҳайдовчи профили топилмади',
          );
        }

        // #19 — транзакция ичида актив брон қулфи
        if (lockSnap.exists) {
          final activeId = lockSnap.data()?['bookingId'] as String?;
          if (activeId != null && activeId.isNotEmpty) {
            final existing = await tx.get(_bookings.doc(activeId));
            if (existing.exists) {
              final st = existing.data()?['status'] as String? ?? '';
              if (st == IntercityBookingStatus.pending ||
                  st == IntercityBookingStatus.confirmed) {
                throw const IntercityBookingException(
                  IntercityBookingErrorKind.alreadyBooked,
                  'Сизда бу ҳайдовчига актив брон мавжуд',
                );
              }
            }
          }
        }

        if (passengerLockSnap.exists) {
          final existingBookingId =
              passengerLockSnap.data()?['bookingId'] as String? ?? '';
          if (existingBookingId.isNotEmpty) {
            final existingRef = _bookings.doc(existingBookingId);
            final existingSnap = await tx.get(existingRef);
            if (existingSnap.exists) {
              final status = existingSnap.data()?['status'] as String? ?? '';
              if (status == IntercityBookingStatus.pending ||
                  status == IntercityBookingStatus.confirmed) {
                throw const IntercityBookingException(
                  IntercityBookingErrorKind.alreadyActive,
                  'Сизда актив брон мавжуд',
                );
              }
            }
          }
        }

        final data = driverData;
        final isListed = (data['isActive'] as bool?) ?? true;
        if (!isListed) {
          throw const IntercityBookingException(
              IntercityBookingErrorKind.driverInactive,
              'Бу рейс энди қабул қилмайди');
        }
        final seats = (data['seats'] as num?)?.toInt() ?? 0;
        if (seats < passengers) {
          throw const IntercityBookingException(
              IntercityBookingErrorKind.notEnoughSeats,
              'Бўш ўринлар етарли эмас');
        }
        // maleCount/femaleCount — CF `updateDriverGenderStats` (onCreate/onUpdate).
        tx.update(driverRef, {
          'seats': seats - passengers,
          'lastBookedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        tx.set(lockRef, {
          'bookingId': bookingRef.id,
          'driverId': driverId,
          'userKey': userKey,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        tx.set(passengerLockRef, {
          'bookingId': bookingRef.id,
          'driverId': driverId,
          'userPhone': canonicalPhoneId(userPhone),
          'createdAt': FieldValue.serverTimestamp(),
        });

        // 2. Booking ҳужжати
        tx.set(bookingRef, {
          'userPhone': canonicalPhoneId(userPhone),
          'userName': userName,
          'userGender': userGender,
          'userBirthDate': userBirthDate,
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
          'driverRouteLabel': IntercityPlaces.rawRouteFromTrip(driverData),
          'createdAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromDate(expiresAt),
          'departureTime': Timestamp.fromDate(departureTime),
          if (initialStatus == IntercityBookingStatus.confirmed)
            'confirmedAt': FieldValue.serverTimestamp(),
          'pickupAddress': '',
          'dropoffNote': '',
          'archivedByDriver': false,
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

        final driverRouteRaw = IntercityPlaces.rawRouteFromTrip(driverData);
        final routeText = IntercityPlaces.shortRouteLabel(driverRouteRaw);

        // 4. Ҳайдовчига push (FCMService `notifications` коллекциясини кузатади)
        if (driverPhone.isNotEmpty) {
          tx.set(notifRef, {
            'targetPhone': notificationTargetPhone(driverPhone),
            'title': initialStatus == IntercityBookingStatus.pending
                ? '🔔 Янги брон сўрови!'
                : '🚗 Янги бронь!',
            'body': intercityDriverBookingAlertBody(
              userName: userName,
              routeLabel: routeText,
              passengers: passengers,
              userPhone: userPhone,
              pricePart: ', ${formatPrice(totalAmount)} сўм',
            ),
            'sent': false,
            'type': initialStatus == IntercityBookingStatus.pending
                ? 'intercity_booking_pending'
                : 'intercity_booking',
            'bookingId': bookingRef.id,
            'priority': 'high',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        if (initialStatus == IntercityBookingStatus.confirmed &&
            userPhone.isNotEmpty) {
          final pNotif = _db.collection('notifications').doc();
          tx.set(pNotif, {
            'targetPhone': notificationTargetPhone(userPhone),
            'title': '✅ $bookingConfirmedTitle',
            'body': pickupRequestBody,
            'sent': false,
            'type': 'intercity_pickup_request',
            'bookingId': bookingRef.id,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } on IntercityBookingException {
      rethrow;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const IntercityBookingException(
          IntercityBookingErrorKind.permissionDenied,
          'booking_permission_denied',
        );
      }
      throw IntercityBookingException(
          IntercityBookingErrorKind.unknown, 'Бронлашда хатолик: ${e.message ?? e.code}');
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
      userGender: userGender,
      userBirthDate: userBirthDate,
      confirmedAt:
          initialStatus == IntercityBookingStatus.confirmed ? now : null,
      driverRouteLabel: IntercityPlaces.rawRouteFromTrip(driverPre.data()),
    );
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

  Future<void> completeBooking({
    required String bookingId,
    required String driverId,
  }) async {
    final ref = _bookings.doc(bookingId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final b = IntercityBooking.fromDoc(snap);
    if (b.driverId != driverId || !b.isActive) return;

    await ref.update({
      'status': IntercityBookingStatus.completed,
      'completedAt': FieldValue.serverTimestamp(),
    });

    final driverRef = _drivers.doc(b.driverId);
    final driverSnap = await driverRef.get();
    if (driverSnap.exists) {
      final data = driverSnap.data() ?? const <String, dynamic>{};
      final driverListed = (data['isActive'] as bool?) ?? true;
      final updates = <String, Object>{
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (driverListed) {
        final currentSeats = (data['seats'] as num?)?.toInt() ?? 0;
        final capacity = (data['seatCapacity'] as num?)?.toInt();
        final restored = currentSeats + b.passengers;
        updates['seats'] = capacity != null
            ? (restored > capacity ? capacity : restored)
            : restored;
      }
      await driverRef.update(updates);
    }

    if (b.userPhone.isNotEmpty) {
      await _writePassengerNotification(
        userPhone: b.userPhone,
        title: '⭐ Сафар якунланди',
        body: '${b.driverName} · ${_bookingRouteNotice(b)}. Раҳмат, яна кўрамиз!',
        type: 'intercity_trip_completed',
        bookingId: bookingId,
      );
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

    IntercityBooking? cancelledBooking;

    try {
      // Аввал booking ҳужжатини олиб, ҳамма ref'ларни тайёрлаб қўямиз —
      // транзакция ичида ҳамма `tx.get`'лар `tx.update`'лардан олдин бўлиши керак.
      final pre = await bookingRef.get();
      if (!pre.exists) return;
      final b = IntercityBooking.fromDoc(pre);
      if (!b.isActive) return;

      final driverRef = _drivers.doc(b.driverId);
      final userKey = canonicalPhoneId(b.userPhone);
      final clientRef = userKey.isNotEmpty
          ? _driverClients(b.driverId).doc(userKey)
          : null;
      final lockRef = userKey.isNotEmpty
          ? _db
              .collection('intercity_booking_locks')
              .doc('${b.driverId}_$userKey')
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
        final lockSnap =
            lockRef != null ? await tx.get(lockRef) : null;

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

        // Qulfni o'chirish auth talab qiladi; bookingId ni tozalash — create/update kabi ochiq.
        if (lockSnap != null && lockSnap.exists) {
          tx.update(lockRef!, {
            'bookingId': FieldValue.delete(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        cancelledBooking = fresh;
      });

      final cb = cancelledBooking;
      if (cb != null && cb.userPhone.isNotEmpty) {
        final r = (reason ?? '').toLowerCase();
        final byDriver = r.contains('ҳайдовчи') || r.contains('haydovchi');
        final tripEnded = r.contains('рейсни бекор') || r.contains('yangi reys');
        await _writePassengerNotification(
          userPhone: cb.userPhone,
          title: tripEnded
              ? '❌ Рейс бекор — бронингиз ҳам ёпилди'
              : byDriver
                  ? '❌ Ҳайдовчи бронни рад этди'
                  : '❌ Брон бекор қилинди',
          body: tripEnded
              ? '${_bookingRouteNotice(cb)}. Ҳайдовчи қайта ишга чиқса, янидан брон қилинг.'
              : byDriver
                  ? '${_bookingRouteNotice(cb)}. Бошқа ҳайдовчи танланг ёки қайта уриниб кўринг.'
                  : '${_bookingRouteNotice(cb)}. Ўринлар қайта бўшатилди.',
          type: 'intercity_booking_cancelled',
          bookingId: bookingId,
        );
      }
    } on IntercityBookingException {
      rethrow;
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const IntercityBookingException(
          IntercityBookingErrorKind.permissionDenied,
          'booking_permission_denied',
        );
      }
      throw const IntercityBookingException(
          IntercityBookingErrorKind.unknown, 'booking_cancel_failed');
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('permission-denied')) {
        throw const IntercityBookingException(
          IntercityBookingErrorKind.permissionDenied,
          'booking_permission_denied',
        );
      }
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
