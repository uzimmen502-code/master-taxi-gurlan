import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/formatters.dart';
import '../models/active_trip.dart';
import '../models/marshrut_driver_option.dart';
import '../models/marshrut_dispatch_event.dart';

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

  /// Qidiruvni bekor qiladi va foydalanuvchi `cancelCount`'ini transaksion
  /// tarzda ko'taradi. 3 marta ketma-ket bekor qilinsa — 30 minutga bloklanadi.
  Future<void> cancelSearch({
    required String tripId,
    required String userPhone,
  }) async {
    if (tripId.isEmpty) return;
    final phone = phoneDigits(userPhone);

    await _db.runTransaction((tx) async {
      final userRef = _users.doc(phone);
      final userDoc = await tx.get(userRef);
      final cancelCount =
          ((userDoc.data()?['cancelCount'] as num?)?.toInt() ?? 0) + 1;

      tx.update(_trips.doc(tripId), {
        'status': 'cancelled',
        'cancelledAt': FieldValue.serverTimestamp(),
      });

      if (cancelCount >= 3) {
        tx.set(
            userRef,
            {
              'cancelCount': 0,
              'blockedUntil': Timestamp.fromDate(
                  DateTime.now().add(const Duration(minutes: 30))),
            },
            SetOptions(merge: true));
      } else {
        tx.set(userRef, {'cancelCount': cancelCount}, SetOptions(merge: true));
      }
    });
  }

  // ─── Marshrut (route taxi) ─────────────────────────────────────────

  /// Marshrut so'rovi yaratiladi va haydovchiga yo'naltirilган tripID qaytariladi.
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
    await _assertNoActiveMarshrutRequest(
      userPhone: userPhone,
      currentSessionId: dispatchSessionId,
    );
    final ref = await _trips.add({
      'userPhone': userPhone,
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
    await _dispatchEvents.add({
      'tripId': ref.id,
      'type': 'offered',
      'dispatchMode': dispatchMode,
      'dispatchSessionId': dispatchSessionId,
      'dispatchAttempt': dispatchAttempt,
      'dispatchTotal': dispatchTotal,
      'userPhone': userPhone,
      'pickupMfy': pickupMfy,
      'dropoffMfy': dropoffMfy,
      'driverId': driver.driverId,
      'driverName': driver.driverName,
      'driverPhone': driver.driverPhone,
      'scheduleId': driver.scheduleId,
      'offerTimeoutSeconds': offerTimeoutSeconds,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> _assertNoActiveMarshrutRequest({
    required String userPhone,
    required String currentSessionId,
  }) async {
    if (userPhone.trim().isEmpty) return;
    final snap = await _trips
        .where('userPhone', isEqualTo: userPhone.trim())
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

  /// Trip'ni oddiy bekor qilish (transaksiyasiz).
  /// Marshrut tarafida cancel hisoblagichi local SharedPreferences'da.
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
  }) async {
    return _db.runTransaction<Map<String, dynamic>?>((tx) async {
      final tripRef = _trips.doc(tripId);
      final tripDoc = await tx.get(tripRef);
      if (!tripDoc.exists) return null;
      final data = tripDoc.data() ?? const <String, dynamic>{};
      final status = (data['status'] ?? '') as String;
      if (status == 'cancelled' || status == 'completed') return null;

      final patch = <String, Object?>{
        'status': 'cancelled',
        'cancelledBy': cancelledBy,
        if (cancelledByPhone.isNotEmpty) 'cancelledByPhone': cancelledByPhone,
        'cancelledAt': FieldValue.serverTimestamp(),
      };
      tx.set(tripRef, patch, SetOptions(merge: true));

      if (status == 'accepted') {
        final scheduleId = (data['scheduleId'] ?? '') as String;
        if (scheduleId.isNotEmpty) {
          tx.set(
            _db.collection('schedules').doc(scheduleId),
            {
              'seatsLeft': FieldValue.increment(1),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        final driverId = (data['acceptedDriverId'] ??
            data['targetDriverId'] ??
            '') as String;
        if (driverId.isNotEmpty) {
          tx.set(
            _queue.doc(driverId),
            {
              'seatsLeft': FieldValue.increment(1),
              'isActive': true,
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
    final ref = _trips.doc(tripId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final data = snap.data();
    if ((data?['status'] ?? '') != 'accepted') return;
    final acceptedDriverId =
        (data?['acceptedDriverId'] ?? data?['targetDriverId'] ?? '') as String;
    if (driverId.isNotEmpty &&
        acceptedDriverId.isNotEmpty &&
        acceptedDriverId != driverId) {
      return;
    }

    await ref.set({
      'status': 'completed',
      'completedBy': completedBy,
      if (completedByPhone.isNotEmpty) 'completedByPhone': completedByPhone,
      'completedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _logDispatchEventFromTrip(
      tripId: tripId,
      type: eventType,
      data: data,
      driverIdOverride: driverId.isNotEmpty ? driverId : null,
    );
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
  /// Atomic ravishda: trip status `pending` tekshiruvi → schedule `seatsLeft`
  /// tekshiruvi (bo'lsa) → ikkalasini birga yangilanadi. Agar trip status
  /// o'zgargan yoki joy qolmagan bo'lsa, `false` qaytaradi.
  Future<bool> acceptMarshrutRide({
    required String tripId,
    String? scheduleId,
    required String driverId,
    required String driverName,
    required String driverPhone,
    required String driverCar,
    required String driverPlate,
  }) async {
    if (tripId.isEmpty) return false;
    Map<String, dynamic>? expiredTripData;
    final accepted = await _db.runTransaction<bool>((tx) async {
      final tripRef = _trips.doc(tripId);
      final tripDoc = await tx.get(tripRef);
      if (!tripDoc.exists) return false;
      final tripData = tripDoc.data() ?? const <String, dynamic>{};
      if ((tripData['status'] ?? '') != 'pending') return false;
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
        return false;
      }

      if (scheduleId != null && scheduleId.isNotEmpty) {
        final schedRef = _db.collection('schedules').doc(scheduleId);
        final schedDoc = await tx.get(schedRef);
        final seats = (schedDoc.data()?['seatsLeft'] as num?)?.toInt() ?? 0;
        if (seats <= 0) {
          tx.update(tripRef, {'status': 'no_seats'});
          return false;
        }
        tx.update(schedRef, {'seatsLeft': seats - 1});
      }

      if (driverId.isNotEmpty) {
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
    }
    return accepted;
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
        'lastRejectedAt': FieldValue.serverTimestamp(),
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
