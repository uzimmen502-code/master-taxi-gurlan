import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/formatters.dart';
import '../core/utils/driver_car_prefill.dart';
import '../models/marshrut_driver_profile.dart';
import '../utils/gurlan_places.dart';
import 'user_repository.dart';

/// Marshrut taksi haydovchisi uchun ma'lumotlar pipeline'i.
///
/// Bir nechta kollektsiyaga yoziladi (profile, drivers, schedules, queue) —
/// shuning uchun `register()` operatsiyasi atomic `WriteBatch` ichida.
class MarshrutDriverRepository {
  MarshrutDriverRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _drivers =>
      _db.collection('drivers');
  CollectionReference<Map<String, dynamic>> get _schedules =>
      _db.collection('schedules');
  CollectionReference<Map<String, dynamic>> get _queue =>
      _db.collection('queue');

  String _canonUid(String raw) => canonicalPhoneId(raw);

  DocumentReference<Map<String, dynamic>> _profileRef(String uid) =>
      _users.doc(_canonUid(uid)).collection('driverProfiles').doc('marshrut');

  /// Marshrut haydovchi profili.
  Future<MarshrutDriverProfile?> getProfile(String uid) async {
    if (uid.isEmpty) return null;
    final snap = await _profileRef(uid).get();
    if (!snap.exists) return null;
    return MarshrutDriverProfile.fromDoc(uid, snap);
  }

  /// Profil (`users/{uid}`) dagi avtomobil → marshrut profil + haydovchi + smena.
  Future<void> syncCarFields({
    required String uid,
    required String carModel,
    required String plate,
    required int seats,
    String? activeScheduleId,
  }) async {
    final id = _canonUid(uid);
    if (id.isEmpty || carModel.trim().isEmpty || plate.trim().isEmpty || seats <= 0) {
      return;
    }
    final model = carModel.trim();
    final plateNorm = plate.trim().toUpperCase();
    final batch = _db.batch();
    final now = FieldValue.serverTimestamp();

    batch.set(
      _profileRef(id),
      {
        'carModel': model,
        'plate': plateNorm,
        'seats': seats,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );

    batch.set(
      _drivers.doc(id),
      {
        'car': model,
        'plate': plateNorm,
        'seats': seats,
        'updatedAt': now,
      },
      SetOptions(merge: true),
    );

    final driverSnap = await _drivers.doc(id).get();

    if (activeScheduleId != null && activeScheduleId.isNotEmpty) {
      final schedRef = _schedules.doc(activeScheduleId);
      final schedSnap = await schedRef.get();
      if (schedSnap.exists) {
        final oldSeats = (schedSnap.data()?['seats'] as num?)?.toInt() ?? seats;
        final seatsLeft =
            (schedSnap.data()?['seatsLeft'] as num?)?.toInt() ?? seats;
        final newLeft = seats > oldSeats
            ? (seatsLeft + (seats - oldSeats)).clamp(0, seats)
            : seatsLeft.clamp(0, seats);
        batch.update(schedRef, {
          'car': model,
          'plate': plateNorm,
          'seats': seats,
          'seatsLeft': newLeft,
          'updatedAt': now,
        });
      }
    }

    final queueRef = _queue.doc(id);
    final queueSnap = await queueRef.get();
    if (queueSnap.exists) {
      final oldSeats = (queueSnap.data()?['seats'] as num?)?.toInt() ?? seats;
      final seatsLeft =
          (queueSnap.data()?['seatsLeft'] as num?)?.toInt() ?? seats;
      final newLeft = seats > oldSeats
          ? (seatsLeft + (seats - oldSeats)).clamp(0, seats)
          : seatsLeft.clamp(0, seats);
      batch.set(
        queueRef,
        {
          'car': model,
          'plate': plateNorm,
          'seats': seats,
          'seatsLeft': newLeft,
          'updatedAt': now,
        },
        SetOptions(merge: true),
      );
    }

    if (driverSnap.exists) {
      final oldSeats = (driverSnap.data()?['seats'] as num?)?.toInt() ?? seats;
      final driverSeatsLeft =
          (driverSnap.data()?['seatsLeft'] as num?)?.toInt() ?? seats;
      final newLeft = seats > oldSeats
          ? (driverSeatsLeft + (seats - oldSeats)).clamp(0, seats)
          : driverSeatsLeft.clamp(0, seats);
      batch.set(
        _drivers.doc(id),
        {
          'seatsLeft': newLeft,
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
  }

  Future<DriverCarPrefill?> resolveCarPrefill(String uid) async {
    if (uid.isEmpty) return null;

    final profileCar =
        await UserRepository().getCarInfo(canonicalPhoneId(uid));
    if (profileCar != null &&
        (profileCar['carModel'] ?? '').isNotEmpty) {
      final seats = int.tryParse(profileCar['carSeats'] ?? '') ?? 0;
      return DriverCarPrefill.fromParts(
        carModel: profileCar['carModel']!,
        plate: profileCar['carPlate'] ?? '',
        seats: seats > 0 ? seats : null,
      );
    }

    final profile = await getProfile(uid);
    if (profile != null && profile.carModel.trim().isNotEmpty) {
      return DriverCarPrefill.fromParts(
        carModel: profile.carModel,
        plate: profile.plate,
      );
    }
    final driverSnap = await _drivers.doc(_canonUid(uid)).get();
    final driverData = driverSnap.data();
    if (driverData != null) {
      final model = DriverCarPrefill.parseModelFromDisplay(
        (driverData['car'] ?? '') as String,
      );
      final plateRaw = (driverData['plate'] ?? '') as String;
      if (model.isNotEmpty && plateRaw.trim().isNotEmpty) {
        return DriverCarPrefill.fromParts(carModel: model, plate: plateRaw);
      }
    }
    final reqSnap = await _db.collection('driver_requests').doc(_canonUid(uid)).get();
    final req = reqSnap.data();
    if (req != null && req['status'] == 'approved') {
      final model = DriverCarPrefill.parseModelFromDisplay(
        (req['car'] ?? '') as String,
      );
      final plateRaw = (req['plate'] ?? '') as String;
      if (model.isNotEmpty && plateRaw.trim().isNotEmpty) {
        return DriverCarPrefill.fromParts(carModel: model, plate: plateRaw);
      }
    }
    return null;
  }

  Future<({String from, String to, List<String> mid})> resolveRoutePrefill(
    String uid,
  ) async {
    if (uid.isEmpty) return (from: '', to: '', mid: const <String>[]);

    final profile = await getProfile(uid);
    if (profile != null && profile.stops.length >= 2) {
      return (
        from: profile.stops.first,
        to: profile.stops.last,
        mid: profile.stops.length > 2
            ? profile.stops.sublist(1, profile.stops.length - 1)
            : const <String>[],
      );
    }

    final reqSnap = await _db.collection('driver_requests').doc(_canonUid(uid)).get();
    final req = reqSnap.data();
    if (req != null) {
      final from = (req['routeFrom'] ?? '') as String;
      final to = (req['routeTo'] ?? '') as String;
      if (from.trim().isNotEmpty && to.trim().isNotEmpty) {
        return (from: from.trim(), to: to.trim(), mid: const <String>[]);
      }
    }

    return (from: '', to: '', mid: const <String>[]);
  }

  /// Haydovchini bugungi reys uchun ro'yxatdan o'tkazadi va onlайн qiladi.
  ///
  /// Atomic ravishda yoziladi:
  /// 1. eski (bugungi) `schedules` deaktivlash
  /// 2. `users/{uid}/driverProfiles/marshrut` profilini saqlash
  /// 3. `drivers/{uid}` ni yangilash (merge)
  /// 4. yangi `schedules/{newId}` yaratish
  /// 5. `queue/{uid}` ga qo'shish
  ///
  /// `scheduleId` qaytariladi.
  Future<String> register({
    required MarshrutDriverProfile profile,
    required String date,
    required DateTime expiresAt,
    required DateTime plannedStartAt,
  }) async {
    final uid = _canonUid(profile.uid);
    if (uid.isEmpty) {
      throw ArgumentError('uid kerak — profilda uid bo\'sh');
    }

    String resolvedModel = profile.carModel;
    String resolvedPlate = profile.plate;

    if (resolvedModel.isEmpty || resolvedPlate.isEmpty) {
      final carUid = canonicalPhoneId(profile.driverPhone);
      final carInfo = await UserRepository().getCarInfo(carUid);
      if (carInfo != null) {
        resolvedModel = carInfo['carModel'] ?? resolvedModel;
        resolvedPlate = carInfo['carPlate'] ?? resolvedPlate;
      }
    }

    // 1. Bugungi eski aktiv reyslarni topish (batch'dan tashqari read)
    final oldSnap = await _schedules
        .where('driverId', isEqualTo: uid)
        .where('date', isEqualTo: date)
        .where('isActive', isEqualTo: true)
        .get();

    final batch = _db.batch();
    for (final doc in oldSnap.docs) {
      batch.update(doc.reference, {'isActive': false});
    }

    final normalizedStops = profile.stops
        .map(GurlanPlaces.normalizeMfyName)
        .toList();
    final fromMfy =
        normalizedStops.isNotEmpty ? normalizedStops.first : '';
    final toMfy = normalizedStops.isNotEmpty ? normalizedStops.last : '';

    // 2. Profile
    batch.set(_profileRef(uid), {
      ...profile.toProfileMap(),
      'carModel': resolvedModel,
      'plate': resolvedPlate,
      'stops': normalizedStops,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final expTs = Timestamp.fromDate(expiresAt);
    final plannedStartTs = Timestamp.fromDate(plannedStartAt);

    // 3. drivers/{uid} — ikkala yozishni bitta `set merge` ga birlashtirdik
    final driverRef = _drivers.doc(uid);
    batch.set(
        driverRef,
        {
          'name': profile.driverName,
          'phone': profile.driverPhone,
          'car': resolvedModel,
          'plate': resolvedPlate,
          'taxiType': 'marshrut',
          'seats': profile.seats,
          'stops': normalizedStops,
          'isOnline': false,
          'isAvailable': true,
          'seatsLeft': profile.seats,
          'startTime': profile.startTime,
          'plannedStartAt': plannedStartTs,
          'todayTrips': 0,
          'todayRejects': 0,
          'todayTimeouts': 0,
          'todayFrom': fromMfy,
          'todayTo': toMfy,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));

    // 4. schedules/{newId}
    final scheduleId = _schedules.doc().id;
    batch.set(_schedules.doc(scheduleId), {
      'driverId': uid,
      'driverName': profile.driverName,
      'driverPhone': profile.driverPhone,
      'car': resolvedModel,
      'plate': resolvedPlate,
      'taxiType': 'marshrut',
      'date': date,
      'from': fromMfy,
      'to': toMfy,
      'stops': normalizedStops,
      'direction': 'forward',
      'seats': profile.seats,
      'seatsLeft': profile.seats,
      'startTime': profile.startTime,
      'plannedStartAt': plannedStartTs,
      'queueEligibleAt': plannedStartTs,
      'todayTrips': 0,
      'todayRejects': 0,
      'todayTimeouts': 0,
      'isActive': true,
      'expiresAt': expTs,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 5. queue/{uid}
    batch.set(_queue.doc(uid), {
      'driverId': uid,
      'driverName': profile.driverName,
      'driverPhone': profile.driverPhone,
      'car': resolvedModel,
      'plate': resolvedPlate,
      'taxiType': 'marshrut',
      'from': fromMfy,
      'to': toMfy,
      'stops': normalizedStops,
      'direction': 'forward',
      'seats': profile.seats,
      'seatsLeft': profile.seats,
      'scheduleId': scheduleId,
      'date': date,
      'startTime': profile.startTime,
      'plannedStartAt': plannedStartTs,
      'queueEligibleAt': plannedStartTs,
      'todayTrips': 0,
      'todayRejects': 0,
      'todayTimeouts': 0,
      'isActive': false,
      'expiresAt': expTs,
    });

    await batch.commit();
    return scheduleId;
  }

  // ─── Online / offline / heartbeat ──────────────────────────────────

  Future<void> goOnline({
    required String uid,
    double? lat,
    double? lng,
    String? scheduleId,
  }) async {
    final id = _canonUid(uid);
    if (id.isEmpty) return;
    final batch = _db.batch();
    final now = DateTime.now();
    final actualOnlineTs = Timestamp.fromDate(now);
    Timestamp? plannedStartTs;
    // Qo'lda online — darhol qidiruv/navbatda; reja vaqti faqat tartiblash uchun.
    final queueEligibleTs = actualOnlineTs;

    if (scheduleId != null && scheduleId.isNotEmpty) {
      final scheduleSnap = await _schedules.doc(scheduleId).get();
      final planned = scheduleSnap.data()?['plannedStartAt'] as Timestamp?;
      if (planned != null) {
        plannedStartTs = planned;
      }
    }

    // drivers/{uid} — onlayn holat va GPS
    batch.set(
      _drivers.doc(id),
      {
        'isOnline': true,
        'taxiType': 'marshrut',
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (plannedStartTs != null) 'plannedStartAt': plannedStartTs,
        'actualOnlineAt': actualOnlineTs,
        'queueEligibleAt': queueEligibleTs,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    // schedules/{scheduleId} — GPS (yo'lovchi qidiruvi uchun)
    if (scheduleId != null &&
        scheduleId.isNotEmpty &&
        lat != null &&
        lng != null) {
      batch.update(_schedules.doc(scheduleId), {
        'lat': lat,
        'lng': lng,
        'actualOnlineAt': actualOnlineTs,
        'queueEligibleAt': queueEligibleTs,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else if (scheduleId != null && scheduleId.isNotEmpty) {
      batch.update(_schedules.doc(scheduleId), {
        'actualOnlineAt': actualOnlineTs,
        'queueEligibleAt': queueEligibleTs,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // queue/{uid} — онлайнга қайтганда навбатга ҳам қайта кирсин.
    batch.set(
      _queue.doc(id),
      {
        'isActive': true,
        'dispatchTimeoutStreak': 0,
        'autoPausedReason': FieldValue.delete(),
        'autoPausedAt': FieldValue.delete(),
        if (plannedStartTs != null) 'plannedStartAt': plannedStartTs,
        'actualOnlineAt': actualOnlineTs,
        'queueEligibleAt': queueEligibleTs,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  Stream<String?> watchAutoPausedReason(String uid) {
    final id = _canonUid(uid);
    if (id.isEmpty) return Stream.value(null);
    return _queue.doc(id).snapshots().map((snap) {
      final d = snap.data();
      if (d == null) return null;
      final reason = (d['autoPausedReason'] ?? '') as String;
      final active = d['isActive'] as bool? ?? false;
      if (reason.isEmpty || active) return null;
      return reason;
    });
  }

  Future<void> reactivateAutoPaused(String uid) async {
    final id = _canonUid(uid);
    if (id.isEmpty) return;
    await _queue.doc(id).set({
      'isActive': true,
      'dispatchTimeoutStreak': 0,
      'autoPausedReason': FieldValue.delete(),
      'autoPausedAt': FieldValue.delete(),
      'reactivatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> goOffline(String uid, {String? scheduleId}) async {
    final id = _canonUid(uid);
    if (id.isEmpty) return;
    // Drivers'ni alohida yangilaymiz — queue doc bo'lmasa ham xatoga uchramaslik
    // uchun. Ikkala operatsiya mustaqil — bittasi kerak bo'lsa, ikkinchisi
    // ishlamasa ham, drivers off'ni saqlash muhim.
    try {
      await _drivers.doc(id).update({
        'isOnline': false,
        'actualOnlineAt': FieldValue.delete(),
        'queueEligibleAt': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
    try {
      await _queue.doc(id).update({
        'isActive': false,
        'actualOnlineAt': FieldValue.delete(),
        'queueEligibleAt': FieldValue.delete(),
      });
    } catch (_) {}
    if (scheduleId != null && scheduleId.isNotEmpty) {
      try {
        await _schedules.doc(scheduleId).update({
          'actualOnlineAt': FieldValue.delete(),
          'queueEligibleAt': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (_) {}
    }
  }

  /// Har 30 sekundda haydovchi va navbat GPS/holatini yangilash.
  Future<void> heartbeat(String uid, {double? lat, double? lng}) async {
    final id = _canonUid(uid);
    if (id.isEmpty) return;
    final patch = <String, Object?>{
      'isOnline': true,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
    };
    if (lat != null) patch['lat'] = lat;
    if (lng != null) patch['lng'] = lng;
    await _drivers.doc(id).update(patch);

    if (lat != null && lng != null) {
      try {
        await _queue.doc(id).set(
          {
            'lat': lat,
            'lng': lng,
            'updatedAt': FieldValue.serverTimestamp(),
            'lastSeenAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } catch (_) {}
    }
  }

  // ─── Direction switch ──────────────────────────────────────────────

  /// Reys tugatildi: yo'nalishni teskari aylantirib, o'rinlarni tiklash.
  /// 3 ta yozish atomar batch'da.
  Future<void> switchDirection({
    required String uid,
    String? scheduleId,
    required String newDirection,
    required int seatsTotal,
  }) async {
    final id = _canonUid(uid);
    if (id.isEmpty) return;
    final batch = _db.batch();
    batch.update(_drivers.doc(id), {
      'isBusy': false,
      'seatsLeft': seatsTotal,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (scheduleId != null && scheduleId.isNotEmpty) {
      batch.update(_schedules.doc(scheduleId), {
        'direction': newDirection,
        'seatsLeft': seatsTotal,
      });
    }
    batch.update(_queue.doc(id), {
      'direction': newDirection,
      'seatsLeft': seatsTotal,
      'isActive': true,
    });
    await batch.commit();
  }

  // ─── Queue position ────────────────────────────────────────────────

  /// Marshrut navbatida o'zining o'rni (1-based). Topilmasa 0 qaytaradi.
  Stream<int> watchQueuePosition({
    required String myDriverId,
    String taxiType = 'marshrut',
  }) {
    final id = _canonUid(myDriverId);
    return _queue
        .where('taxiType', isEqualTo: taxiType)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snap) {
      final docs = snap.docs.toList()..sort(_compareFairQueueDocs);
      for (var i = 0; i < docs.length; i++) {
        if (docs[i].id == id) return i + 1;
      }
      return 0;
    });
  }

  int _compareFairQueueDocs(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final ad = a.data();
    final bd = b.data();
    final byEligible = _compareTs(ad['queueEligibleAt'] as Timestamp?,
        bd['queueEligibleAt'] as Timestamp?);
    if (byEligible != 0) return byEligible;

    final byTrips = ((ad['todayTrips'] as num?)?.toInt() ?? 0)
        .compareTo((bd['todayTrips'] as num?)?.toInt() ?? 0);
    if (byTrips != 0) return byTrips;

    final aMisses = ((ad['todayRejects'] as num?)?.toInt() ?? 0) +
        ((ad['todayTimeouts'] as num?)?.toInt() ?? 0);
    final bMisses = ((bd['todayRejects'] as num?)?.toInt() ?? 0) +
        ((bd['todayTimeouts'] as num?)?.toInt() ?? 0);
    final byMisses = aMisses.compareTo(bMisses);
    if (byMisses != 0) return byMisses;

    final byActual = _compareTs(
        ad['actualOnlineAt'] as Timestamp?, bd['actualOnlineAt'] as Timestamp?);
    if (byActual != 0) return byActual;

    return _compareTs(
        ad['onlineAt'] as Timestamp?, bd['onlineAt'] as Timestamp?);
  }

  int _compareTs(Timestamp? a, Timestamp? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  // ─── Crowdsourced route coordinates ────────────────────────────────

  static String routeKey(String from, String to) {
    String norm(String s) =>
        s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), '_');
    return '${norm(from)}__${norm(to)}';
  }

  Future<Map<String, dynamic>?> getRouteCoordinates(
    String from,
    String to,
  ) async {
    final key = routeKey(from, to);
    final snap = await _db.collection('marshrut_coordinates').doc(key).get();
    if (!snap.exists) return null;
    final d = snap.data()!;
    if (!(d['isLocked'] as bool? ?? false)) return null;
    return d;
  }

  Future<bool> contributeRouteCoordinates({
    required String from,
    required String to,
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
    required String driverId,
  }) async {
    final key = routeKey(from, to);
    final ref = _db.collection('marshrut_coordinates').doc(key);

    return _db.runTransaction((t) async {
      final snap = await t.get(ref);

      if (snap.exists && (snap.data()!['isLocked'] as bool? ?? false)) {
        return false;
      }

      final existing = snap.exists ? snap.data()! : null;
      final contributions = List<Map<String, dynamic>>.from(
        (existing?['contributions'] as List<dynamic>? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map)),
      );

      if (contributions.any((c) => c['driverId'] == driverId)) {
        return false;
      }

      contributions.add({
        'driverId': driverId,
        'startLat': startLat,
        'startLng': startLng,
        'endLat': endLat,
        'endLng': endLng,
      });

      final count = contributions.length;
      double avg(String field) => contributions
              .map((c) => (c[field] as num).toDouble())
              .reduce((a, b) => a + b) /
          count;

      final avgStartLat = avg('startLat');
      final avgStartLng = avg('startLng');
      final avgEndLat = avg('endLat');
      final avgEndLng = avg('endLng');

      t.set(
        ref,
        {
          'from': from,
          'to': to,
          'confirmCount': count,
          'isLocked': count >= 3,
          'startLat': avgStartLat,
          'startLng': avgStartLng,
          'endLat': avgEndLat,
          'endLng': avgEndLng,
          'contributions': contributions,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      return true;
    });
  }
}
