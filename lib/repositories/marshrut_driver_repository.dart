import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/marshrut_driver_profile.dart';

/// Marshrut taksi haydovchisi uchun ma'lumotlar pipeline'i.
///
/// Bir nechta kollektsiyaga yoziladi (profile, drivers, schedules, queue) —
/// shuning uchun `register()` operatsiyasi atomic `WriteBatch` ichida.
class MarshrutDriverRepository {
  MarshrutDriverRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _drivers =>
      _db.collection('drivers');
  CollectionReference<Map<String, dynamic>> get _schedules =>
      _db.collection('schedules');
  CollectionReference<Map<String, dynamic>> get _queue => _db.collection('queue');

  DocumentReference<Map<String, dynamic>> _profileRef(String uid) =>
      _users.doc(uid).collection('driverProfiles').doc('marshrut');

  /// Marshrut haydovchi profili.
  Future<MarshrutDriverProfile?> getProfile(String uid) async {
    if (uid.isEmpty) return null;
    final snap = await _profileRef(uid).get();
    if (!snap.exists) return null;
    return MarshrutDriverProfile.fromDoc(uid, snap);
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
  }) async {
    final uid = profile.uid;
    if (uid.isEmpty) {
      throw ArgumentError('uid kerak — profilda uid bo\'sh');
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

    // 2. Profile
    batch.set(_profileRef(uid), {
      ...profile.toProfileMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final fromMfy = profile.stops.isNotEmpty ? profile.stops.first : '';
    final toMfy = profile.stops.isNotEmpty ? profile.stops.last : '';

    // 3. drivers/{uid} — ikkala yozishni bitta `set merge` ga birlashtirdik
    final driverRef = _drivers.doc(uid);
    batch.set(
        driverRef,
        {
          'name': profile.driverName,
          'phone': profile.driverPhone,
          'car': profile.carModel,
          'plate': profile.plate,
          'taxiType': 'marshrut',
          'seats': profile.seats,
          'stops': profile.stops,
          'isOnline': false,
          'isAvailable': true,
          'seatsLeft': profile.seats,
          'todayFrom': fromMfy,
          'todayTo': toMfy,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));

    // 4. schedules/{newId}
    final scheduleId = _schedules.doc().id;
    final expTs = Timestamp.fromDate(expiresAt);
    batch.set(_schedules.doc(scheduleId), {
      'driverId': uid,
      'driverName': profile.driverName,
      'driverPhone': profile.driverPhone,
      'car': profile.carModel,
      'plate': profile.plate,
      'taxiType': 'marshrut',
      'date': date,
      'from': fromMfy,
      'to': toMfy,
      'stops': profile.stops,
      'direction': 'forward',
      'seats': profile.seats,
      'seatsLeft': profile.seats,
      'isActive': true,
      'expiresAt': expTs,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 5. queue/{uid}
    batch.set(_queue.doc(uid), {
      'driverId': uid,
      'driverName': profile.driverName,
      'driverPhone': profile.driverPhone,
      'car': profile.carModel,
      'plate': profile.plate,
      'taxiType': 'marshrut',
      'from': fromMfy,
      'to': toMfy,
      'stops': profile.stops,
      'direction': 'forward',
      'seats': profile.seats,
      'seatsLeft': profile.seats,
      'scheduleId': scheduleId,
      'date': date,
      'onlineAt': FieldValue.serverTimestamp(),
      'isActive': true,
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
    if (uid.isEmpty) return;
    final batch = _db.batch();

    // drivers/{uid} — onlayn holat va GPS
    batch.set(
      _drivers.doc(uid),
      {
        'isOnline': true,
        'taxiType': 'marshrut',
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
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
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // queue/{uid} — онлайнга қайтганда навбатга ҳам қайта кирсин.
    batch.set(
      _queue.doc(uid),
      {
        'isActive': true,
        'dispatchTimeoutStreak': 0,
        'autoPausedReason': FieldValue.delete(),
        'autoPausedAt': FieldValue.delete(),
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  Stream<String?> watchAutoPausedReason(String uid) {
    if (uid.isEmpty) return Stream.value(null);
    return _queue.doc(uid).snapshots().map((snap) {
      final d = snap.data();
      if (d == null) return null;
      final reason = (d['autoPausedReason'] ?? '') as String;
      final active = d['isActive'] as bool? ?? false;
      if (reason.isEmpty || active) return null;
      return reason;
    });
  }

  Future<void> reactivateAutoPaused(String uid) async {
    if (uid.isEmpty) return;
    await _queue.doc(uid).set({
      'isActive': true,
      'dispatchTimeoutStreak': 0,
      'autoPausedReason': FieldValue.delete(),
      'autoPausedAt': FieldValue.delete(),
      'reactivatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> goOffline(String uid) async {
    if (uid.isEmpty) return;
    // Drivers'ni alohida yangilaymiz — queue doc bo'lmasa ham xatoga uchramaslik
    // uchun. Ikkala operatsiya mustaqil — bittasi kerак bo'lsa, ikkinchisi
    // ishlamasa ham, drivers off'ni saqlash muhim.
    try {
      await _drivers.doc(uid).update({
        'isOnline': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
    try {
      await _queue.doc(uid).update({'isActive': false});
    } catch (_) {}
  }

  /// Har 30 sekundda `drivers/{uid}` `updatedAt`'ni yangilash —
  /// "men hali tirikman" signali.
  Future<void> heartbeat(String uid) async {
    if (uid.isEmpty) return;
    await _drivers.doc(uid).update({
      'isOnline': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
    if (uid.isEmpty) return;
    final batch = _db.batch();
    batch.update(_drivers.doc(uid), {
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
    batch.update(_queue.doc(uid), {
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
    return _queue
        .where('taxiType', isEqualTo: taxiType)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snap) {
      final docs = snap.docs.toList()
        ..sort((a, b) {
          final at = a.data()['onlineAt'] as Timestamp?;
          final bt = b.data()['onlineAt'] as Timestamp?;
          if (at == null) return 1;
          if (bt == null) return -1;
          return at.compareTo(bt);
        });
      for (var i = 0; i < docs.length; i++) {
        if (docs[i].id == myDriverId) return i + 1;
      }
      return 0;
    });
  }
}
