import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/formatters.dart';
import '../models/active_trip.dart';
import '../models/marshrut_driver_option.dart';
import '../models/marshrut_dispatch_event.dart';

/// Marshrut qabul natijasi — UI xabarlari uchun.
class MarshrutAcceptOutcome {
  const MarshrutAcceptOutcome._(this.ok, this.code);

  final bool ok;
  final String? code;

  static const success = MarshrutAcceptOutcome._(true, null);
  static const expired = MarshrutAcceptOutcome._(false, 'expired');
  static const noSeats = MarshrutAcceptOutcome._(false, 'no_seats');
  static const taken = MarshrutAcceptOutcome._(false, 'taken');
}

/// `trips` collection bilan ishlash — qidiruv, status kuzatish, bekor qilish.
///
/// `TripsRepository` (yakunlangan safarlar uchun) bilan adashtirмасланг.
/// Ikkalasini birlashtirsa ham bo'lardi, lekin "active vs history" — tabiiy
/// ajratish. Keyinchalik kerak bo'lsa бирлаштириш osongina.
class RidesRepository {
  RidesRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _trips =>
      _db.collection('trips');
  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _dispatchEvents =>
      _db.collection('marshrut_dispatch_events');
  CollectionReference<Map<String, dynamic>> get _queue =>
      _db.collection('queue');
  CollectionReference<Map<String, dynamic>> get _drivers =>
      _db.collection('drivers');
  DocumentReference<Map<String, dynamic>> get _appSettings =>
      _db.collection('settings').doc('app');

  int _normalizeTimeoutAutoPauseStreak(Object? raw) {
    final value = (raw as num?)?.toInt() ?? 3;
    if (value < 1) return 3;
    if (value > 20) return 20;
    return value;
  }

  int _normalizeMarshrutOfferTimeoutSeconds(Object? raw) {
    final value = (raw as num?)?.toInt() ?? 15;
    if (value < 5) return 15;
    if (value > 120) return 120;
    return value;
  }

  Stream<int> watchMarshrutTimeoutAutoPauseStreak() {
    return _appSettings.snapshots().map((snap) {
      return _normalizeTimeoutAutoPauseStreak(
        snap.data()?['marshrutTimeoutAutoPauseStreak'],
      );
    });
  }

  Future<int> getMarshrutTimeoutAutoPauseStreak() async {
    final snap = await _appSettings.get();
    return _normalizeTimeoutAutoPauseStreak(
      snap.data()?['marshrutTimeoutAutoPauseStreak'],
    );
  }

  Future<void> setMarshrutTimeoutAutoPauseStreak(int value) async {
    await _appSettings.set({
      'marshrutTimeoutAutoPauseStreak': _normalizeTimeoutAutoPauseStreak(value),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Stream<int> watchMarshrutOfferTimeoutSeconds() {
    return _appSettings.snapshots().map((snap) {
      return _normalizeMarshrutOfferTimeoutSeconds(
        snap.data()?['marshrutOfferTimeoutSeconds'],
      );
    });
  }

  Future<int> getMarshrutOfferTimeoutSeconds() async {
    final snap = await _appSettings.get();
    return _normalizeMarshrutOfferTimeoutSeconds(
      snap.data()?['marshrutOfferTimeoutSeconds'],
    );
  }

  Future<void> setMarshrutOfferTimeoutSeconds(int value) async {
    await _appSettings.set({
      'marshrutOfferTimeoutSeconds':
          _normalizeMarshrutOfferTimeoutSeconds(value),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Yangi qidiruv yaratiladi va trip ID qaytariladi.
  Future<String> createSearchRequest({
    required String userPhone,
    required String fromAddr,
    required String toAddr,
    required double fromLat,
    required double fromLng,
    required String taxiType,
    double initialRadiusKm = 3,
    Duration ttl = const Duration(minutes: 3),
  }) async {
    final expiresAt = DateTime.now().add(ttl);
    final ref = await _trips.add({
      'status': 'searching',
      'userPhone': userPhone,
      'fromAddr': fromAddr,
      'toAddr': toAddr,
      'fromLat': fromLat,
      'fromLng': fromLng,
      'taxiType': taxiType,
      'radiusKm': initialRadiusKm,
      'driverId': '',
      'driverName': '',
      'price': 0,
      'cancelCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'expiresAt': Timestamp.fromDate(expiresAt),
    });
    return ref.id;
  }

  Stream<ActiveTrip> watch(String tripId) =>
      _trips.doc(tripId).snapshots().map(ActiveTrip.fromDoc);

  Stream<List<ActiveTrip>> watchActiveMarshrutTripsForAdmin({
    int limit = 100,
  }) {
    return _trips
        .where('taxiType', isEqualTo: 'marshrut')
        .where('status', whereIn: ['pending', 'accepted'])
        .limit(limit)
        .snapshots()
        .map((snap) {
          final trips = snap.docs.map(ActiveTrip.fromDoc).toList();
          trips.sort((a, b) {
            final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bd.compareTo(ad);
          });
          return trips;
        });
  }

  Stream<List<MarshrutDispatchEvent>> watchRecentMarshrutDispatchEvents({
    int limit = 200,
  }) {
    return _dispatchEvents
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(MarshrutDispatchEvent.fromDoc).toList());
  }

  Future<void> updateSearchRadius(String tripId, double radiusKm) async {
    await _trips.doc(tripId).update({'radiusKm': radiusKm});
  }

  /// Қидирув жараёнидa йўловчи рўйхатдан тaнлaган драйверни `trips/{id}`га
  /// ёзамиз. Driver app `targetDriverId == self_uid AND status == searching`
  /// тинглaгaнидaн сўнг шу ҳужжатни кўрaди ва `TripRequestScreen`'ни очaди.
  ///
  /// Драйвер рад этсa, ўз тарафидaн `targetDriverId=''` қилaди (ёки timeout):
  /// йўловчи бошқа драйверни танлaб шу мaтодни яна чaқирa олaди.
  Future<void> targetDriver({
    required String tripId,
    required String driverId,
  }) async {
    if (tripId.isEmpty || driverId.isEmpty) return;
    await _trips.doc(tripId).update({
      'targetDriverId': driverId,
      'targetedAt': FieldValue.serverTimestamp(),
    });
  }

  // ─── Local taxi (qidiruv bekor) ─────────────────────────────────────
  //
  // Faqat `taxiType != 'marshrut'` qidiruvlari. Marshrut blokiga tegishli emas.

  /// Qidiruvni bekor qiladi (`status: cancelled`, `cancelReason: search_cancelled`).
  Future<void> cancelSearch({
    required String tripId,
  }) async {
    if (tripId.isEmpty) return;
    await _trips.doc(tripId).update({
      'status': 'cancelled',
      'cancelledBy': 'passenger',
      'cancelReason': 'search_cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
    });
  }

  /// Qabul qilingan mahalliy safarni yo'lovchi bekor qiladi.
  Future<void> cancelLocalTripByPassenger(String tripId) async {
    await _db.runTransaction((t) async {
      final ref = _trips.doc(tripId);
      final snap = await t.get(ref);
      if (!snap.exists) return;
      final data = snap.data()!;
      final status = data['status'] as String? ?? '';

      if (status != 'accepted') return;

      final driverId = data['driverId'] as String? ?? '';

      t.update(ref, {
        'status': 'cancelled',
        'cancelledBy': 'passenger',
        'cancelReason': 'passenger_cancel_during_trip',
        'cancelledAt': FieldValue.serverTimestamp(),
      });

      if (driverId.isNotEmpty) {
        t.update(
          _db.collection('drivers').doc(driverId),
          {
            'isBusy': false,
            'updatedAt': FieldValue.serverTimestamp(),
          },
        );
      }
    });
  }

  // ─── Marshrut (route taxi) ─────────────────────────────────────────

  static String normalizeMarshrutPhone(String phone) =>
      phoneDigits(phone.trim());

  DocumentReference<Map<String, dynamic>> _marshrutActiveRef(String phone) =>
      _users.doc(phone).collection('marshrut_state').doc('active');

  /// Marshrut so'rovi yaratiladi va haydovchiga yo'naltirilgan tripID qaytariladi.
  Future<String> createMarshrutRequest({
    required String userPhone,
    required String pickupMfy,
    required String pickupAddr,
    required String dropoffMfy,
    required MarshrutDriverOption driver,
    double? userLat,
    double? userLng,
    int dispatchAttempt = 1,
    int dispatchTotal = 1,
    String dispatchMode = 'queue',
    String dispatchSessionId = '',
    Duration ttl = const Duration(seconds: 18),
    int offerTimeoutSeconds = 0,
  }) async {
    final phone = normalizeMarshrutPhone(userPhone);
    await _assertNoActiveMarshrutRequest(
      userPhone: phone,
      currentSessionId: dispatchSessionId,
    );
    final tripId = await _db.runTransaction<String>((tx) async {
      await _assertNoActiveMarshrutRequestTx(
        tx,
        userPhone: phone,
        currentSessionId: dispatchSessionId,
      );

      final tripRef = _trips.doc();
      tx.set(tripRef, {
        'userPhone': phone,
        'pickupMfy': pickupMfy,
        'pickupAddr': pickupAddr,
        'dropoffMfy': dropoffMfy,
        'taxiType': 'marshrut',
        'status': 'pending',
        'targetDriverId': driver.driverId,
        'driverName': driver.driverName,
        'driverPhone': driver.driverPhone,
        'driverCar': driver.car,
        'driverPlate': driver.plate,
        'scheduleId': driver.scheduleId,
        'fare': driver.price,
        'userLat': userLat,
        'userLng': userLng,
        'driverLat': driver.lat,
        'driverLng': driver.lng,
        'dispatchMode': dispatchMode,
        'dispatchSessionId': dispatchSessionId,
        'dispatchAttempt': dispatchAttempt,
        'dispatchTotal': dispatchTotal,
        'offerTimeoutSeconds': offerTimeoutSeconds,
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(ttl)),
      });

      if (phone.isNotEmpty) {
        tx.set(
          _marshrutActiveRef(phone),
          {
            'tripId': tripRef.id,
            'sessionId': dispatchSessionId,
            'status': 'pending',
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      return tripRef.id;
    });

    await _dispatchEvents.add({
      'tripId': tripId,
      'type': 'offered',
      'dispatchMode': dispatchMode,
      'dispatchSessionId': dispatchSessionId,
      'dispatchAttempt': dispatchAttempt,
      'dispatchTotal': dispatchTotal,
      'userPhone': phone,
      'pickupMfy': pickupMfy,
      'dropoffMfy': dropoffMfy,
      'driverId': driver.driverId,
      'driverName': driver.driverName,
      'driverPhone': driver.driverPhone,
      'scheduleId': driver.scheduleId,
      'offerTimeoutSeconds': offerTimeoutSeconds,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return tripId;
  }

  /// Pending marshrut taklifini yopish (navbatda keyingi haydovchiga o'tish / dispose).
  Future<void> closeMarshrutOfferIfPending(String tripId) async {
    if (tripId.isEmpty) return;
    final snap = await _trips.doc(tripId).get();
    if (!snap.exists) return;
    if ((snap.data()?['status'] ?? '') == 'pending') {
      await markExpired(tripId);
    }
  }

  Future<void> _assertNoActiveMarshrutRequestTx(
    Transaction tx, {
    required String userPhone,
    required String currentSessionId,
  }) async {
    final phone = normalizeMarshrutPhone(userPhone);
    if (phone.isEmpty) return;

    final activeRef = _marshrutActiveRef(phone);
    final activeSnap = await tx.get(activeRef);
    if (!activeSnap.exists) return;

    final active = activeSnap.data() ?? const <String, dynamic>{};
    final existingTripId = (active['tripId'] ?? '') as String;
    final sessionId = (active['sessionId'] ?? '') as String;
    if (existingTripId.isEmpty) return;

    if (sessionId.isNotEmpty &&
        sessionId == currentSessionId &&
        currentSessionId.isNotEmpty) {
      return;
    }

    final tripSnap = await tx.get(_trips.doc(existingTripId));
    if (!tripSnap.exists) return;

    final d = tripSnap.data() ?? const <String, dynamic>{};
    final status = (d['status'] ?? '') as String;
    if (status == 'pending' && _isExpiredTripData(d)) {
      tx.set(
        tripSnap.reference,
        {
          'status': 'expired',
          'expiredAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      tx.set(
        activeRef,
        {
          'status': 'expired',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return;
    }
    if (status == 'pending' || status == 'accepted') {
      throw StateError('active_marshrut_request_exists');
    }
  }

  Future<void> _clearMarshrutActiveIfMatches({
    required String userPhone,
    required String tripId,
    String status = 'cleared',
  }) async {
    final phone = normalizeMarshrutPhone(userPhone);
    if (phone.isEmpty || tripId.isEmpty) return;
    final ref = _marshrutActiveRef(phone);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;
      final activeTripId = (snap.data()?['tripId'] ?? '') as String;
      if (activeTripId != tripId) return;
      tx.set(
        ref,
        {
          'status': status,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> _assertNoActiveMarshrutRequest({
    required String userPhone,
    required String currentSessionId,
  }) async {
    final phone = normalizeMarshrutPhone(userPhone);
    if (phone.isEmpty) return;
    final snap = await _trips
        .where('userPhone', isEqualTo: phone)
        .where('taxiType', isEqualTo: 'marshrut')
        .where('status', whereIn: ['pending', 'accepted']).get();
    for (final doc in snap.docs) {
      final d = doc.data();
      final status = (d['status'] ?? '') as String;
      final sessionId = (d['dispatchSessionId'] ?? '') as String;
      if (sessionId.isNotEmpty && sessionId == currentSessionId) continue;
      if (status == 'pending' && _isExpiredTripData(d)) {
        await markExpired(doc.id);
        continue;
      }
      if (status == 'pending' || status == 'accepted') {
        throw StateError('active_marshrut_request_exists');
      }
    }
  }

  bool _isExpiredTripData(Map<String, dynamic> data) {
    final expiresAt = data['expiresAt'] as Timestamp?;
    if (expiresAt == null) return false;
    return !expiresAt.toDate().isAfter(DateTime.now());
  }

  /// Trip'ni "muddati tugаgan" deb belgilash (timeout).
  Future<void> markExpired(String tripId) async {
    if (tripId.isEmpty) return;
    final data = await _expirePendingTripInTransaction(tripId);
    if (data == null) return;
    await _applyDispatchPolicy(
      type: 'timeout',
      data: data,
    );
    await _logDispatchEventFromTrip(
      tripId: tripId,
      type: 'timeout',
      data: data,
    );
    await _clearMarshrutActiveIfMatches(
      userPhone: (data['userPhone'] ?? '') as String,
      tripId: tripId,
      status: 'expired',
    );
  }

  Future<Map<String, dynamic>?> _expirePendingTripInTransaction(
    String tripId,
  ) async {
    return _db.runTransaction<Map<String, dynamic>?>((tx) async {
      final ref = _trips.doc(tripId);
      final snap = await tx.get(ref);
      if (!snap.exists) return null;
      final data = snap.data() ?? const <String, dynamic>{};
      if ((data['status'] ?? '') != 'pending') return null;
      tx.set(
        ref,
        {
          'status': 'expired',
          'expiredAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return data;
    });
  }

  /// Marshrut pending taklifini bekor qilish (navbat / timeout / dispose).
  /// Yo'lovchi blok hisobi CF `onTripUpdate` → `marshrut_block/state`.
  Future<void> markCancelled(String tripId) async {
    if (tripId.isEmpty) return;
    final data = await _cancelMarshrutTripInTransaction(tripId: tripId);
    if (data == null) return;
    await _resetDriverDispatchStats(
      (data['acceptedDriverId'] ?? data['targetDriverId']) as String?,
    );
    await _logDispatchEventFromTrip(
      tripId: tripId,
      type: 'cancelled',
      data: data,
    );
    await _clearMarshrutActiveIfMatches(
      userPhone: (data['userPhone'] ?? '') as String,
      tripId: tripId,
      status: 'cancelled',
    );
  }

  /// Yo'lovchi qabul qilingan marshrut safarini bekor qiladi.
  Future<void> cancelMarshrutByPassenger({
    required String tripId,
    required String reason,
  }) async {
    if (tripId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final phone = normalizeMarshrutPhone(prefs.getString('user_phone') ?? '');

    await _db.runTransaction((t) async {
      final tripRef = _trips.doc(tripId);
      final tripSnap = await t.get(tripRef);
      if (!tripSnap.exists) return;

      final data = tripSnap.data() ?? const <String, dynamic>{};
      final scheduleId = (data['scheduleId'] ?? '') as String;
      final driverId = (data['acceptedDriverId'] ?? '') as String;

      t.update(tripRef, {
        'status': 'cancelled',
        'cancelledBy': 'passenger',
        'cancelReason': reason,
        'cancelledAt': FieldValue.serverTimestamp(),
        'notifyPassengerReroute': false,
      });

      if (scheduleId.isNotEmpty) {
        final schedRef = _db.collection('schedules').doc(scheduleId);
        final schedSnap = await t.get(schedRef);
        if (schedSnap.exists) {
          final schedData = schedSnap.data() ?? const <String, dynamic>{};
          final seats = (schedData['seats'] as num?)?.toInt() ?? 1;
          final seatsLeft =
              ((schedData['seatsLeft'] as num?)?.toInt() ?? 0) + 1;
          final clamped = seatsLeft.clamp(0, seats);
          t.update(schedRef, {
            'seatsLeft': clamped,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      if (driverId.isNotEmpty) {
        final queueRef = _queue.doc(driverId);
        final queueSnap = await t.get(queueRef);
        if (queueSnap.exists) {
          final queueData = queueSnap.data() ?? const <String, dynamic>{};
          final seats = (queueData['seats'] as num?)?.toInt() ?? 1;
          final seatsLeft =
              ((queueData['seatsLeft'] as num?)?.toInt() ?? 0) + 1;
          final clamped = seatsLeft.clamp(0, seats);
          t.update(queueRef, {
            'seatsLeft': clamped,
            'isActive': true,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        final driverRef = _drivers.doc(driverId);
        t.set(
          driverRef,
          {
            'isBusy': false,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      if (phone.isNotEmpty) {
        t.set(
          _marshrutActiveRef(phone),
          {
            'status': 'cancelled',
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    });

    try {
      final snap = await _trips.doc(tripId).get();
      final tripData = snap.data();
      await _db.collection('marshrut_dispatch_events').add({
        'tripId': tripId,
        'type': 'passenger_cancel_after_accept',
        'cancelledBy': 'passenger',
        'cancelReason': reason,
        'driverId': tripData?['acceptedDriverId'],
        'userPhone': tripData?['userPhone'],
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// Bitta trip hujjatini o'qish (push navigatsiya va accepted ekran).
  Future<ActiveTrip?> getTrip(String tripId) async {
    if (tripId.isEmpty) return null;
    final snap = await _trips.doc(tripId).get();
    if (!snap.exists) return null;
    return ActiveTrip.fromDoc(snap);
  }

  /// Haydovchi majburiy chiqqanda faol safarni bekor qilish.
  Future<void> cancelMarshrutByDriver({
    required String tripId,
    required String reason,
  }) async {
    if (tripId.isEmpty) return;
    final data = await _cancelMarshrutTripInTransaction(
      tripId: tripId,
      cancelledBy: 'driver',
      cancelReason: reason,
      requireAccepted: true,
    );
    if (data == null) return;
    try {
      await _trips.doc(tripId).update({'cancelledByMode': 'force_leave'});
    } catch (_) {}
    await _resetDriverDispatchStats(
      (data['acceptedDriverId'] ?? data['targetDriverId']) as String?,
    );
    await _logDispatchEventFromTrip(
      tripId: tripId,
      type: 'driver_force_leave_cancel',
      data: data,
    );
  }

  /// Ҳайдовчи accepted tripni бекор қилади (машина тўлиқ / жой йўқ).
  /// Йўловчига қайта dispatch: [notifyPassengerReroute] + [cancelReason].
  Future<void> cancelMarshrutAcceptedByDriver({
    required String tripId,
    required String driverId,
    bool noRoom = true,
  }) async {
    if (tripId.isEmpty || driverId.isEmpty) return;
    final data = await _cancelMarshrutTripInTransaction(
      tripId: tripId,
      cancelledBy: 'driver',
      cancelledByPhone: driverId,
      cancelReason: noRoom ? 'no_room' : 'driver_other',
      notifyPassengerReroute: noRoom,
      requireAccepted: true,
      requireDriverId: driverId,
    );
    if (data == null) return;
    await _resetDriverDispatchStats(driverId);
    await _logDispatchEventFromTrip(
      tripId: tripId,
      type: noRoom ? 'driver_cancelled_no_room' : 'driver_cancelled',
      data: data,
    );
  }

  Future<void> adminCancelMarshrutTrip({
    required String tripId,
    String operatorPhone = '',
  }) async {
    if (tripId.isEmpty) return;
    final data = await _cancelMarshrutTripInTransaction(
      tripId: tripId,
      cancelledBy: 'admin',
      cancelledByPhone: operatorPhone.trim(),
    );
    if (data == null) return;
    await _resetDriverDispatchStats(
      (data['acceptedDriverId'] ?? data['targetDriverId']) as String?,
    );
    await _logDispatchEventFromTrip(
      tripId: tripId,
      type: 'admin_cancelled',
      data: data,
    );
  }

  Future<Map<String, dynamic>?> _cancelMarshrutTripInTransaction({
    required String tripId,
    String cancelledBy = 'user',
    String cancelledByPhone = '',
    String cancelReason = '',
    bool notifyPassengerReroute = false,
    bool requireAccepted = false,
    String requireDriverId = '',
  }) async {
    return _db.runTransaction<Map<String, dynamic>?>((tx) async {
      final tripRef = _trips.doc(tripId);
      final tripDoc = await tx.get(tripRef);
      if (!tripDoc.exists) return null;
      final data = tripDoc.data() ?? const <String, dynamic>{};
      final status = (data['status'] ?? '') as String;
      if (status == 'cancelled' || status == 'completed') return null;
      if (requireAccepted && status != 'accepted') return null;
      if (requireDriverId.isNotEmpty) {
        final acceptedId = (data['acceptedDriverId'] ?? '') as String;
        if (acceptedId != requireDriverId) return null;
      }

      final patch = <String, Object?>{
        'status': 'cancelled',
        'cancelledBy': cancelledBy,
        if (cancelledByPhone.isNotEmpty) 'cancelledByPhone': cancelledByPhone,
        if (cancelReason.isNotEmpty) 'cancelReason': cancelReason,
        if (notifyPassengerReroute) 'notifyPassengerReroute': true,
        'cancelledAt': FieldValue.serverTimestamp(),
      };
      tx.set(tripRef, patch, SetOptions(merge: true));

      if (status == 'accepted') {
        final scheduleId = (data['scheduleId'] ?? '') as String;
        final driverId = (data['acceptedDriverId'] ??
            data['targetDriverId'] ??
            '') as String;
        await _releaseMarshrutSeatInTransaction(
          tx,
          scheduleId: scheduleId,
          driverId: driverId,
        );
        if (driverId.isNotEmpty) {
          tx.set(
            _drivers.doc(driverId),
            {
              'isBusy': false,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      }

      return data;
    });
  }

  Future<void> completeMarshrutRide({
    required String tripId,
    required String driverId,
  }) async {
    await _completeMarshrutRide(
      tripId: tripId,
      driverId: driverId,
      completedBy: driverId,
      eventType: 'completed',
    );
  }

  Future<void> adminCompleteMarshrutTrip({
    required String tripId,
    required String driverId,
    String operatorPhone = '',
  }) async {
    await _completeMarshrutRide(
      tripId: tripId,
      driverId: driverId,
      completedBy: 'admin',
      completedByPhone: operatorPhone.trim(),
      eventType: 'admin_completed',
    );
  }

  Future<void> _completeMarshrutRide({
    required String tripId,
    required String driverId,
    required String completedBy,
    String completedByPhone = '',
    required String eventType,
  }) async {
    if (tripId.isEmpty) return;
    Map<String, dynamic>? tripData;
    await _db.runTransaction((tx) async {
      final tripRef = _trips.doc(tripId);
      final tripDoc = await tx.get(tripRef);
      if (!tripDoc.exists) return;
      tripData = tripDoc.data() ?? const <String, dynamic>{};
      if ((tripData!['status'] ?? '') != 'accepted') return;
      final acceptedDriverId = (tripData!['acceptedDriverId'] ??
          tripData!['targetDriverId'] ??
          '') as String;
      if (driverId.isNotEmpty &&
          acceptedDriverId.isNotEmpty &&
          acceptedDriverId != driverId) {
        tripData = null;
        return;
      }

      tx.set(
        tripRef,
        {
          'status': 'completed',
          'completedBy': completedBy,
          if (completedByPhone.isNotEmpty)
            'completedByPhone': completedByPhone,
          'completedAt': FieldValue.serverTimestamp(),
          'fare': (tripData!['fare'] as num?)?.toInt() ?? 0,
          'cashPaid': (tripData!['fare'] as num?)?.toInt() ?? 0,
        },
        SetOptions(merge: true),
      );

      final scheduleId = (tripData!['scheduleId'] ?? '') as String;
      final seatDriverId = acceptedDriverId.isNotEmpty
          ? acceptedDriverId
          : (tripData!['targetDriverId'] ?? '') as String;
      await _releaseMarshrutSeatInTransaction(
        tx,
        scheduleId: scheduleId,
        driverId: seatDriverId,
      );
      if (seatDriverId.isNotEmpty) {
        tx.set(
          _drivers.doc(seatDriverId),
          {
            'isBusy': false,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    });

    if (tripData == null) return;
    await _logDispatchEventFromTrip(
      tripId: tripId,
      type: eventType,
      data: tripData,
      driverIdOverride: driverId.isNotEmpty ? driverId : null,
    );
    await _clearMarshrutActiveIfMatches(
      userPhone: (tripData!['userPhone'] ?? '') as String,
      tripId: tripId,
      status: 'completed',
    );
  }

  /// `schedules.seatsLeft` — единствен манба; queue faqat `isActive` (+ mirror seatsLeft).
  Future<void> _releaseMarshrutSeatInTransaction(
    Transaction tx, {
    required String scheduleId,
    required String driverId,
  }) async {
    if (scheduleId.isEmpty) return;
    final schedRef = _db.collection('schedules').doc(scheduleId);
    final schedDoc = await tx.get(schedRef);
    if (!schedDoc.exists) return;
    final data = schedDoc.data() ?? const <String, dynamic>{};
    final seats = (data['seatsLeft'] as num?)?.toInt() ?? 0;
    final total = (data['seats'] as num?)?.toInt() ?? 0;
    final cap = total > 0 ? total : seats + 1;
    final next = (seats + 1).clamp(0, cap);
    tx.set(
      schedRef,
      {
        'seatsLeft': next,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    if (driverId.isNotEmpty) {
      tx.set(
        _queue.doc(driverId),
        {
          'seatsLeft': next,
          'isActive': next > 0,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
  }

  // ─── Marshrut driver — pending requests ────────────────────────────

  /// Berilgan haydovchiga yo'naltirilган pending'lar (real-time).
  Stream<List<ActiveTrip>> watchPendingForDriver(
    String driverId, {
    String? taxiType,
  }) {
    if (driverId.isEmpty) return Stream.value(const []);
    Query<Map<String, dynamic>> q = _trips
        .where('targetDriverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'pending');
    if (taxiType != null) {
      q = q.where('taxiType', isEqualTo: taxiType);
    }
    return q.snapshots().map((s) {
      final list = s.docs.map(ActiveTrip.fromDoc).where((trip) {
        return !trip.isExpired;
      }).toList();
      list.sort((a, b) {
        final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });
      return list;
    });
  }

  /// Bir martalik o'qish — masalan, app resume'dan keyin chekka holatlar uchun.
  Future<List<ActiveTrip>> getPendingForDriver(
    String driverId, {
    String? taxiType,
  }) async {
    if (driverId.isEmpty) return const [];
    Query<Map<String, dynamic>> q = _trips
        .where('targetDriverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'pending');
    if (taxiType != null) {
      q = q.where('taxiType', isEqualTo: taxiType);
    }
    final snap = await q.get();
    final list = snap.docs.map(ActiveTrip.fromDoc).where((trip) {
      return !trip.isExpired;
    }).toList();
    list.sort((a, b) {
      final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });
    return list;
  }

  Stream<List<ActiveTrip>> watchAcceptedForDriver(
    String driverId, {
    String? taxiType,
  }) {
    if (driverId.isEmpty) return Stream.value(const []);
    Query<Map<String, dynamic>> q = _trips
        .where('acceptedDriverId', isEqualTo: driverId)
        .where('status', isEqualTo: 'accepted');
    if (taxiType != null) {
      q = q.where('taxiType', isEqualTo: taxiType);
    }
    return q.snapshots().map((s) {
      final list = s.docs.map(ActiveTrip.fromDoc).toList();
      list.sort((a, b) {
        final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });
      return list;
    });
  }

  /// Marshrut haydovchi safarni qabul qiladi.
  ///
  /// `schedules.seatsLeft` — единствен манба; queue faqat mirror + isActive.
  Future<MarshrutAcceptOutcome> acceptMarshrutRide({
    required String tripId,
    String? scheduleId,
    required String driverId,
    required String driverName,
    required String driverPhone,
    required String driverCar,
    required String driverPlate,
  }) async {
    if (tripId.isEmpty) return MarshrutAcceptOutcome.taken;
    Map<String, dynamic>? expiredTripData;
    String? failCode;
    final accepted = await _db.runTransaction<bool>((tx) async {
      final tripRef = _trips.doc(tripId);
      final tripDoc = await tx.get(tripRef);
      if (!tripDoc.exists) {
        failCode = 'taken';
        return false;
      }
      final tripData = tripDoc.data() ?? const <String, dynamic>{};
      if ((tripData['status'] ?? '') != 'pending') {
        failCode = 'taken';
        return false;
      }
      if (_isExpiredTripData(tripData)) {
        expiredTripData = tripData;
        tx.set(
            tripRef,
            {
              'status': 'expired',
              'expiredAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
        tx.set(_dispatchEvents.doc(), {
          'tripId': tripId,
          'type': 'timeout',
          'dispatchMode': tripData['dispatchMode'] ?? 'queue',
          'dispatchSessionId': tripData['dispatchSessionId'] ?? '',
          'dispatchAttempt': tripData['dispatchAttempt'] ?? 1,
          'dispatchTotal': tripData['dispatchTotal'] ?? 1,
          'offerTimeoutSeconds': tripData['offerTimeoutSeconds'] ?? 0,
          'userPhone': tripData['userPhone'] ?? '',
          'pickupMfy': tripData['pickupMfy'] ?? '',
          'dropoffMfy': tripData['dropoffMfy'] ?? '',
          'driverId': driverId,
          'driverName': driverName,
          'driverPhone': driverPhone,
          'scheduleId': scheduleId ?? tripData['scheduleId'] ?? '',
          'createdAt': FieldValue.serverTimestamp(),
        });
        failCode = 'expired';
        return false;
      }

      final schedId = scheduleId ?? (tripData['scheduleId'] ?? '') as String;
      var seatsAfter = 0;
      if (schedId.isNotEmpty) {
        final schedRef = _db.collection('schedules').doc(schedId);
        final schedDoc = await tx.get(schedRef);
        final seats = (schedDoc.data()?['seatsLeft'] as num?)?.toInt() ?? 0;
        if (seats <= 0) {
          tx.update(tripRef, {'status': 'no_seats'});
          failCode = 'no_seats';
          return false;
        }
        seatsAfter = seats - 1;
        tx.update(schedRef, {
          'seatsLeft': seatsAfter,
          'todayTrips': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      if (driverId.isNotEmpty) {
        final driverRef = _db.collection('drivers').doc(driverId);
        tx.set(
          driverRef,
          {
            'todayTrips': FieldValue.increment(1),
            'isBusy': true,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        if (schedId.isNotEmpty) {
          tx.set(
            _queue.doc(driverId),
            {
              'seatsLeft': seatsAfter,
              'isActive': seatsAfter > 0,
              'todayTrips': FieldValue.increment(1),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      }

      tx.update(tripRef, {
        'status': 'accepted',
        'acceptedDriverId': driverId,
        'acceptedDriverName': driverName,
        'acceptedDriverPhone': driverPhone,
        'acceptedDriverCar': driverCar,
        'acceptedDriverPlate': driverPlate,
        'acceptedAt': FieldValue.serverTimestamp(),
      });
      tx.set(_dispatchEvents.doc(), {
        'tripId': tripId,
        'type': 'accepted',
        'dispatchMode': tripDoc.data()?['dispatchMode'] ?? 'queue',
        'dispatchSessionId': tripDoc.data()?['dispatchSessionId'] ?? '',
        'dispatchAttempt': tripDoc.data()?['dispatchAttempt'] ?? 1,
        'dispatchTotal': tripDoc.data()?['dispatchTotal'] ?? 1,
        'offerTimeoutSeconds': tripDoc.data()?['offerTimeoutSeconds'] ?? 0,
        'userPhone': tripDoc.data()?['userPhone'] ?? '',
        'pickupMfy': tripDoc.data()?['pickupMfy'] ?? '',
        'dropoffMfy': tripDoc.data()?['dropoffMfy'] ?? '',
        'driverId': driverId,
        'driverName': driverName,
        'driverPhone': driverPhone,
        'scheduleId': scheduleId ?? tripDoc.data()?['scheduleId'] ?? '',
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (driverId.isNotEmpty) {
        tx.set(
            _queue.doc(driverId),
            {
              'dispatchTimeoutStreak': 0,
              'lastAcceptedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true));
      }
      return true;
    });
    if (expiredTripData != null) {
      await _applyDispatchPolicy(
        type: 'timeout',
        data: expiredTripData,
        driverIdOverride: driverId,
      );
      return MarshrutAcceptOutcome.expired;
    }
    if (accepted) {
      final tripSnap = await _trips.doc(tripId).get();
      final userPhone =
          normalizeMarshrutPhone((tripSnap.data()?['userPhone'] ?? '') as String);
      if (userPhone.isNotEmpty) {
        try {
          await _marshrutActiveRef(userPhone).set(
            {
              'tripId': tripId,
              'sessionId': tripSnap.data()?['dispatchSessionId'] ?? '',
              'status': 'accepted',
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        } catch (_) {
          // Qoidalar yangilanmaguncha qabul muvaffaqiyatli qolsin.
        }
      }
      return MarshrutAcceptOutcome.success;
    }
    if (failCode == 'no_seats') return MarshrutAcceptOutcome.noSeats;
    if (failCode == 'expired') return MarshrutAcceptOutcome.expired;
    return MarshrutAcceptOutcome.taken;
  }

  Future<void> rejectRide({
    required String tripId,
    required String driverId,
  }) async {
    if (tripId.isEmpty) return;
    final data = await _db.runTransaction<Map<String, dynamic>?>((tx) async {
      final ref = _trips.doc(tripId);
      final snap = await tx.get(ref);
      if (!snap.exists) return null;
      final data = snap.data() ?? const <String, dynamic>{};
      if ((data['status'] ?? '') != 'pending') return null;
      tx.set(
          ref,
          {
            'status': 'rejected',
            'rejectedBy': driverId,
            'rejectedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true));
      return data;
    });
    if (data == null) return;
    await _applyDispatchPolicy(
      type: 'rejected',
      data: data,
      driverIdOverride: driverId,
    );
    await _logDispatchEventFromTrip(
      tripId: tripId,
      type: 'rejected',
      data: data,
      driverIdOverride: driverId,
    );
    final passengerPhone = (data['userPhone'] ?? '') as String;
    if (passengerPhone.isNotEmpty) {
      await _clearMarshrutActiveIfMatches(
        userPhone: passengerPhone,
        tripId: tripId,
        status: 'rejected',
      );
    }
  }

  Future<void> _logDispatchEventFromTrip({
    required String tripId,
    required String type,
    required Map<String, dynamic>? data,
    String? driverIdOverride,
  }) async {
    final d = data ?? const <String, dynamic>{};
    await _dispatchEvents.add({
      'tripId': tripId,
      'type': type,
      'dispatchMode': d['dispatchMode'] ?? 'queue',
      'dispatchSessionId': d['dispatchSessionId'] ?? '',
      'dispatchAttempt': d['dispatchAttempt'] ?? 1,
      'dispatchTotal': d['dispatchTotal'] ?? 1,
      'userPhone': d['userPhone'] ?? '',
      'pickupMfy': d['pickupMfy'] ?? '',
      'dropoffMfy': d['dropoffMfy'] ?? '',
      'driverId': driverIdOverride ?? d['targetDriverId'] ?? '',
      'driverName': d['driverName'] ?? '',
      'driverPhone': d['driverPhone'] ?? '',
      'scheduleId': d['scheduleId'] ?? '',
      'offerTimeoutSeconds': d['offerTimeoutSeconds'] ?? 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _applyDispatchPolicy({
    required String type,
    required Map<String, dynamic>? data,
    String? driverIdOverride,
  }) async {
    final d = data ?? const <String, dynamic>{};
    final driverId = driverIdOverride ?? (d['targetDriverId'] ?? '') as String;
    if (driverId.isEmpty) return;

    final queueRef = _queue.doc(driverId);
    if (type == 'rejected') {
      await queueRef.set({
        'dispatchRejectCount': FieldValue.increment(1),
        'todayRejects': FieldValue.increment(1),
        'lastRejectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final scheduleId = (d['scheduleId'] ?? '') as String;
      if (scheduleId.isNotEmpty) {
        await _db.collection('schedules').doc(scheduleId).set({
          'todayRejects': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await _db.collection('drivers').doc(driverId).set({
        'todayRejects': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }

    if (type == 'timeout') {
      final timeoutAutoPauseStreak = await getMarshrutTimeoutAutoPauseStreak();
      var disabled = false;
      var streakAfter = 0;
      await _db.runTransaction((tx) async {
        final queueDoc = await tx.get(queueRef);
        if (!queueDoc.exists) return;
        final streak =
            (queueDoc.data()?['dispatchTimeoutStreak'] as num?)?.toInt() ?? 0;
        streakAfter = streak + 1;
        final patch = <String, Object?>{
          'dispatchTimeoutStreak': streakAfter,
          'dispatchTimeoutCount': FieldValue.increment(1),
          'todayTimeouts': FieldValue.increment(1),
          'lastTimeoutAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        if (streakAfter >= timeoutAutoPauseStreak) {
          disabled = true;
          patch['isActive'] = false;
          patch['autoPausedReason'] = 'dispatch_timeout_streak';
          patch['autoPausedAt'] = FieldValue.serverTimestamp();
        }
        tx.set(queueRef, patch, SetOptions(merge: true));
      });

      final scheduleId = (d['scheduleId'] ?? '') as String;
      if (scheduleId.isNotEmpty) {
        await _db.collection('schedules').doc(scheduleId).set({
          'todayTimeouts': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await _db.collection('drivers').doc(driverId).set({
        'todayTimeouts': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (disabled) {
        await _dispatchEvents.add({
          'tripId': d['tripId'] ?? '',
          'type': 'driver_auto_paused',
          'dispatchMode': d['dispatchMode'] ?? 'queue',
          'dispatchSessionId': d['dispatchSessionId'] ?? '',
          'dispatchAttempt': d['dispatchAttempt'] ?? 1,
          'dispatchTotal': d['dispatchTotal'] ?? 1,
          'userPhone': d['userPhone'] ?? '',
          'pickupMfy': d['pickupMfy'] ?? '',
          'dropoffMfy': d['dropoffMfy'] ?? '',
          'driverId': driverId,
          'driverName': d['driverName'] ?? '',
          'driverPhone': d['driverPhone'] ?? '',
          'scheduleId': d['scheduleId'] ?? '',
          'offerTimeoutSeconds': d['offerTimeoutSeconds'] ?? 0,
          'reason': '$timeoutAutoPauseStreak consecutive timeouts',
          'timeoutStreak': streakAfter,
          'timeoutAutoPauseStreak': timeoutAutoPauseStreak,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    }
  }

  Future<void> _resetDriverDispatchStats(String? driverId) async {
    if (driverId == null || driverId.isEmpty) return;
    await _queue.doc(driverId).set({
      'dispatchTimeoutStreak': 0,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ─── Driver home screen — universal trips stream ─────────────────────

  /// `searching`/`pending` ҳолатидаги охирги 20 та трипни кузатиш.
  /// Сlient тарафда taxi тури ва вақт бўйича фильтрланади.
  Stream<List<ActiveTrip>> watchPendingTrips({int limit = 20}) {
    return _trips
        .where('status', whereIn: ['searching', 'pending'])
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(ActiveTrip.fromDoc).toList());
  }

  /// Универсал ride accept — alone, marshrut, intercity учун ягона транзакция.
  /// Trip status `searching`/`pending` бўлгандагина олинади. Marshrut'да scheduleId
  /// бўлса, joy кaмaйтирилади.
  /// Натижа: `(success, errorCode)`. `errorCode`: `'no_seats'` | `'taken'` | `null`.
  Future<({bool success, String? errorCode})> acceptRide({
    required String tripId,
    required String driverId,
    required String driverName,
    required String driverPhone,
    required String driverCar,
    required String driverPlate,
    String? scheduleId,
    String? taxiType,
  }) async {
    if (tripId.isEmpty) {
      return (success: false, errorCode: 'taken');
    }
    try {
      await _db.runTransaction((tx) async {
        final tripRef = _trips.doc(tripId);
        final tripDoc = await tx.get(tripRef);
        if (!tripDoc.exists) throw Exception('taken');
        final status = (tripDoc.data()?['status'] ?? '') as String;
        if (status != 'searching' && status != 'pending') {
          throw Exception('taken');
        }
        if (taxiType == 'marshrut' &&
            scheduleId != null &&
            scheduleId.isNotEmpty) {
          final schedRef = _db.collection('schedules').doc(scheduleId);
          final schedDoc = await tx.get(schedRef);
          final seats = (schedDoc.data()?['seatsLeft'] as num?)?.toInt() ?? 0;
          if (seats <= 0) {
            tx.update(tripRef, {'status': 'no_seats'});
            throw Exception('no_seats');
          }
          tx.update(schedRef, {'seatsLeft': seats - 1});
        }
        if (taxiType == 'marshrut' && driverId.isNotEmpty) {
          final queueRef = _db.collection('queue').doc(driverId);
          final queueDoc = await tx.get(queueRef);
          if (queueDoc.exists) {
            final queueSeats =
                (queueDoc.data()?['seatsLeft'] as num?)?.toInt() ?? 0;
            final nextSeats = queueSeats > 0 ? queueSeats - 1 : 0;
            tx.set(
                queueRef,
                {
                  'seatsLeft': nextSeats,
                  if (nextSeats <= 0) 'isActive': false,
                  'updatedAt': FieldValue.serverTimestamp(),
                },
                SetOptions(merge: true));
          }
        }
        tx.update(tripRef, {
          'status': 'accepted',
          'acceptedDriverId': driverId,
          'acceptedDriverName': driverName,
          'acceptedDriverPhone': driverPhone,
          'acceptedDriverCar': driverCar,
          'acceptedDriverPlate': driverPlate,
          'acceptedAt': FieldValue.serverTimestamp(),
        });
      });
      return (success: true, errorCode: null);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('no_seats')) {
        return (success: false, errorCode: 'no_seats');
      }
      return (success: false, errorCode: 'taken');
    }
  }

  /// Сафарни якунлаш — `status: 'completed'`, `fare`, `cashPaid` ёзилади.
  Future<void> finishTrip({
    required String tripId,
    required int fare,
    required int cashPaid,
  }) async {
    if (tripId.isEmpty) return;
    try {
      await _trips.doc(tripId).update({
        'status': 'completed',
        'fare': fare,
        'cashPaid': cashPaid,
        'completedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}
