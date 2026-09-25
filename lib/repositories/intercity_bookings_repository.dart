import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../core/l10n/offline_l10n.dart';
import '../core/service_config_holder.dart';
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
  IntercityBookingsRepository({FirebaseFirestore? db, FirebaseFunctions? fns})
      : _db = db ?? FirebaseFirestore.instance,
        _fns = fns ?? FirebaseFunctions.instance;

  final FirebaseFirestore _db;

  /// Ўрин (`seats`) фақат серверда ўзгаради — қуйидаги callable'лар
  /// орқали. Мижозда бу майдонга ёзиш Firestore Rules'да ёпилган.
  final FirebaseFunctions _fns;

  /// CF хатолигини UI кутадиган [IntercityBookingException]га айлантиради.
  ///
  /// CF `message` сифатида аниқ калит қайтаради (`notEnoughSeats`,
  /// `driverInactive`...), шунинг учун хабарлар ўзгармайди.
  static Never _throwFromCf(FirebaseFunctionsException e) {
    final msg = e.message ?? '';
    switch (msg) {
      case 'notEnoughSeats':
        throw const IntercityBookingException(
            IntercityBookingErrorKind.notEnoughSeats,
            'Бўш ўринлар етарли эмас');
      case 'driverInactive':
        throw const IntercityBookingException(
            IntercityBookingErrorKind.driverInactive,
            'Бу рейс энди қабул қилмайди');
      case 'driverNotFound':
        throw const IntercityBookingException(
            IntercityBookingErrorKind.driverNotFound,
            'Ҳайдовчи профили топилмади');
      case 'alreadyBooked':
        throw const IntercityBookingException(
            IntercityBookingErrorKind.alreadyBooked,
            'Сизда бу ҳайдовчига актив брон мавжуд');
      case 'alreadyActive':
        throw const IntercityBookingException(
            IntercityBookingErrorKind.alreadyActive, 'Сизда актив брон мавжуд');
      case 'ride_not_accepting':
        throw const IntercityBookingException(
            IntercityBookingErrorKind.unknown, 'ride_not_accepting');
    }
    if (e.code == 'unauthenticated' || e.code == 'permission-denied') {
      throw const IntercityBookingException(
        IntercityBookingErrorKind.permissionDenied,
        'booking_permission_denied',
      );
    }
    throw IntercityBookingException(
        IntercityBookingErrorKind.unknown, 'Бронлашда хатолик: $msg');
  }

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

  // `clients` aggregation'и энди фақат серверда янгиланади
  // (`createIntercityBooking` / `cancelIntercityBooking`), шунинг учун
  // бу ерда унга ёзиладиган ҳавола қолмади.

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

  /// Ишончли бронь — `createIntercityBooking` callable орқали.
  ///
  /// Бутун транзакция СЕРВЕРДА бажарилади:
  ///   1. Ҳайдовчи ҳужжати текширилади (`isActive`, `seats < passengers`)
  ///      ва `seats` камайтирилади;
  ///   2. `intercity_bookings/{id}` яратилади;
  ///   3. `clients` aggregation ошади; 4. `notifications` ёзилади.
  ///
  /// Илгари шу транзакция МИЖОЗДА эди ва қоидалар `seats` майдонини
  /// ҳар кимга очиқ қолдирарди. Йўловчи телефони ҳам энди `data`дан
  /// эмас, токендан олинади — бошқа одам номидан брон қилиб бўлмайди.
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

    // Ҳайдовчи ҳужжати — фақат КЎРСАТИШ учун (маршрут ёрлиғи, автомат
    // тасдиқ). Ҳақиқий текширув серверда: CF ўз транзакциясида яна
    // ўқийди, шунинг учун бу ерда эскирган қиймат хавф туғдирмайди.
    final driverPre = await _drivers.doc(driverId).get();
    if (!driverPre.exists) {
      throw const IntercityBookingException(
        IntercityBookingErrorKind.driverNotFound,
        'Ҳайдовчи профили топилмади',
      );
    }
    final driverData = driverPre.data() ?? const <String, dynamic>{};
    final driverRouteRaw = IntercityPlaces.rawRouteFromTrip(driverData);
    final routeText = IntercityPlaces.shortRouteLabel(driverRouteRaw);

    final pickupRequestBody =
        await OfflineL10n.tr('intercity_pickup_request_body');
    final bookingConfirmedTitle =
        await OfflineL10n.tr('booking_confirmed_title');

    final now = DateTime.now();
    final expiresAt = now.add(const Duration(minutes: 30));

    String bookingId;
    String initialStatus;
    try {
      final res = await _fns.httpsCallable('createIntercityBooking').call({
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
        'driverRouteLabel': driverRouteRaw,
        // Матнлар мижозда тайёрланади — CF'да l10n йўқ.
        'driverAlertBody': intercityDriverBookingAlertBody(
          userName: userName,
          routeLabel: routeText,
          passengers: passengers,
          userPhone: userPhone,
          pricePart: ', ${formatMoney(totalAmount)}',
        ),
        'confirmedTitle': '✅ $bookingConfirmedTitle',
        'pickupBody': pickupRequestBody,
        'reportStamp': ServiceConfigHolder.reportStamp(),
      });
      final data = Map<String, dynamic>.from(res.data as Map);
      bookingId = (data['bookingId'] as String?) ?? '';
      initialStatus =
          (data['status'] as String?) ?? IntercityBookingStatus.pending;
    } on FirebaseFunctionsException catch (e) {
      _throwFromCf(e);
    } catch (e) {
      throw IntercityBookingException(
          IntercityBookingErrorKind.unknown, 'Бронлашда хатолик: $e');
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
      status: initialStatus,
      createdAt: now,
      expiresAt: expiresAt,
      departureTime: departureTime,
      userGender: userGender,
      userBirthDate: userBirthDate,
      confirmedAt:
          initialStatus == IntercityBookingStatus.confirmed ? now : null,
      driverRouteLabel: driverRouteRaw,
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

  /// Сафар якунланди — `completeIntercityBooking` callable.
  ///
  /// Статус, ўринни қайтариш ва йўловчига хабар — ҳаммаси серверда:
  /// `seats` майдонига мижоз ёза олмайди.
  Future<void> completeBooking({
    required String bookingId,
    required String driverId,
  }) async {
    final snap = await _bookings.doc(bookingId).get();
    if (!snap.exists) return;
    final b = IntercityBooking.fromDoc(snap);
    if (b.driverId != driverId || !b.isActive) return;

    try {
      await _fns.httpsCallable('completeIntercityBooking').call({
        'bookingId': bookingId,
        'notifyTitle': '⭐ Сафар якунланди',
        'notifyBody':
            '${b.driverName} · ${_bookingRouteNotice(b)}. Раҳмат, яна кўрамиз!',
      });
    } on FirebaseFunctionsException catch (e) {
      _throwFromCf(e);
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

  /// Ҳайдовчи рейсни ёпганда ёки янги рейс очганда — барча pending/confirmed
  /// бронлар. Бир чақирувда: CF ўзи рўйхатни олади ва битталаб бекор қилади
  /// (илгари мижоз ҳар бир брон учун алоҳида транзакция юритарди).
  Future<int> cancelActiveBookingsForDriver(
    String driverId, {
    String reason = 'Ҳайдовчи рейсни бекор қилди',
  }) async {
    if (driverId.isEmpty) return 0;
    try {
      final res = await _fns.httpsCallable('cancelIntercityBooking').call({
        'driverId': driverId,
        'reason': reason,
        'notifyTitle': '❌ Рейс бекор — бронингиз ҳам ёпилди',
        'notifyBody': 'Ҳайдовчи қайта ишга чиқса, янидан брон қилинг.',
      });
      final data = Map<String, dynamic>.from(res.data as Map);
      return (data['cancelled'] as num?)?.toInt() ?? 0;
    } catch (e) {
      debugPrint('cancelActiveBookingsForDriver: $e');
      return 0;
    }
  }

  /// Мижоз ёки ҳайдовчи бекор қилади — `cancelIntercityBooking` callable.
  ///
  /// Серверда: статус `cancelled`, ҳайдовчида `seats` қайтарилади (сиғимдан
  /// ошмайди), `clients` aggregation камаяди, қулф тозаланади ва йўловчига
  /// хабар ёзилади. CF чақирувчи брон тарафи эканини ўзи текширади.
  Future<void> cancelBooking({
    required String bookingId,
    String? reason,
  }) async {
    final pre = await _bookings.doc(bookingId).get();
    if (!pre.exists) return;
    final b = IntercityBooking.fromDoc(pre);
    if (!b.isActive) return;

    final r = (reason ?? '').toLowerCase();
    final byDriver = r.contains('ҳайдовчи') || r.contains('haydovchi');
    final tripEnded = r.contains('рейсни бекор') || r.contains('yangi reys');

    try {
      await _fns.httpsCallable('cancelIntercityBooking').call({
        'bookingId': bookingId,
        'reason': reason ?? '',
        'notifyTitle': tripEnded
            ? '❌ Рейс бекор — бронингиз ҳам ёпилди'
            : byDriver
                ? '❌ Ҳайдовчи бронни рад этди'
                : '❌ Брон бекор қилинди',
        'notifyBody': tripEnded
            ? '${_bookingRouteNotice(b)}. Ҳайдовчи қайта ишга чиқса, янидан брон қилинг.'
            : byDriver
                ? '${_bookingRouteNotice(b)}. Бошқа ҳайдовчи танланг ёки қайта уриниб кўринг.'
                : '${_bookingRouteNotice(b)}. Ўринлар қайта бўшатилди.',
      });
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unauthenticated' || e.code == 'permission-denied') {
        throw const IntercityBookingException(
          IntercityBookingErrorKind.permissionDenied,
          'booking_permission_denied',
        );
      }
      throw const IntercityBookingException(
          IntercityBookingErrorKind.unknown, 'booking_cancel_failed');
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
