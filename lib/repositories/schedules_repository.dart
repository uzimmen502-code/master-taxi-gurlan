import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/schedule.dart';

/// `schedules` collection — marshrut taksi haydovchilarining kunlik reyslari.
class SchedulesRepository {
  SchedulesRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('schedules');

  Future<Schedule?> getById(String id) async {
    if (id.isEmpty) return null;
    final snap = await _col.doc(id).get();
    if (!snap.exists) return null;
    return Schedule.fromDoc(snap);
  }

  /// Bugungi sanaga belgilangan, aktiv marshrut reyslarini qaytaradi.
  /// Filtirlash (yo'nalish, masofa, expired) chaqiruvchi tarafda — bu yerda
  /// faqat raw Firestore so'rovi.
  Future<List<Schedule>> searchActiveToday({
    required String date,
    String taxiType = 'marshrut',
  }) async {
    final snap = await _col
        .where('taxiType', isEqualTo: taxiType)
        .where('date', isEqualTo: date)
        .where('isActive', isEqualTo: true)
        .get();
    return snap.docs.map(Schedule.fromDoc).toList(growable: false);
  }

  /// Bugungi haydovchi aktiv reysi (bo'lsa).
  Future<Schedule?> getTodayActiveForDriver({
    required String driverId,
    required String date,
    String taxiType = 'marshrut',
  }) async {
    if (driverId.isEmpty) return null;
    final snap = await _col
        .where('driverId', isEqualTo: driverId)
        .where('taxiType', isEqualTo: taxiType)
        .where('date', isEqualTo: date)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return Schedule.fromDoc(snap.docs.first);
  }

  /// `taxiType` фильтрисиз — har қайси таxi турдаги aktiv reys.
  /// Driver home screen учун — у йерда бугунги ҳар қандай аctiv reys текширилади.
  Future<Schedule?> getTodayActiveForDriverAnyType({
    required String driverId,
    required String date,
  }) async {
    if (driverId.isEmpty) return null;
    final snap = await _col
        .where('driverId', isEqualTo: driverId)
        .where('date', isEqualTo: date)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return Schedule.fromDoc(snap.docs.first);
  }

  /// Бугунги ҳайдовчининг aktiv reys'и бор-йўқлиги (тeзкор тeкширув).
  Future<bool> hasActiveToday({
    required String driverId,
    required String date,
  }) async {
    if (driverId.isEmpty) return false;
    final snap = await _col
        .where('driverId', isEqualTo: driverId)
        .where('date', isEqualTo: date)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  /// Муддати ўтган aktiv reys'ларни ёпиш. Ҳеч бўлмаса биттаси
  /// ёпилган бўлса `true` қайтаради.
  Future<bool> closeExpiredForDriver(String driverId) async {
    if (driverId.isEmpty) return false;
    try {
      final now = Timestamp.now();
      final snap = await _col
          .where('driverId', isEqualTo: driverId)
          .where('isActive', isEqualTo: true)
          .get();
      final batch = _db.batch();
      bool hasExpired = false;
      var deactivateIntercity = false;
      for (final doc in snap.docs) {
        final exp = doc.data()['expiresAt'] as Timestamp?;
        if (exp != null && exp.compareTo(now) < 0) {
          batch.update(doc.reference, {'isActive': false});
          hasExpired = true;
          if ((doc.data()['taxiType'] as String?) == 'intercity') {
            deactivateIntercity = true;
          }
        }
      }
      if (deactivateIntercity) {
        batch.update(_db.collection('intercity_drivers').doc(driverId), {
          'isActive': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      if (hasExpired) await batch.commit();
      return hasExpired;
    } catch (_) {
      return false;
    }
  }

  /// Иш кунини якунлаш — бугунги барча aktiv reys'ларни ёпиш.
  Future<void> endTodayWork({
    required String driverId,
    required String date,
  }) async {
    if (driverId.isEmpty) return;
    try {
      final snap = await _col
          .where('driverId', isEqualTo: driverId)
          .where('date', isEqualTo: date)
          .where('isActive', isEqualTo: true)
          .get();
      final batch = _db.batch();
      var hadIntercity = false;
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'isActive': false});
        if ((doc.data()['taxiType'] as String?) == 'intercity') {
          hadIntercity = true;
        }
      }
      if (hadIntercity) {
        batch.update(_db.collection('intercity_drivers').doc(driverId), {
          'isActive': false,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (_) {}
  }

  /// Бугунги aktiv reys'дa `seatsLeft` ни 1 ўзгартириш (қўшимча йўловчи).
  Future<int?> adjustSeatsToday({
    required String driverId,
    required String date,
    required int delta,
  }) async {
    if (driverId.isEmpty) return null;
    try {
      final snap = await _col
          .where('driverId', isEqualTo: driverId)
          .where('date', isEqualTo: date)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      final current = (snap.docs.first.data()['seatsLeft'] ?? 0) as int;
      if (delta < 0 && current <= 0) return current;
      await snap.docs.first.reference.update({
        'seatsLeft': FieldValue.increment(delta),
      });
      return current + delta;
    } catch (_) {
      return null;
    }
  }

  /// O'rin yoki yo'nalishni yangilash.
  Future<void> updateSeatsAndDirection({
    required String scheduleId,
    required int seatsLeft,
    String? direction,
  }) async {
    if (scheduleId.isEmpty) return;
    await _col.doc(scheduleId).update({
      'seatsLeft': seatsLeft,
      if (direction != null) 'direction': direction,
    });
  }

  /// Haydovchining bugungi reysini ro'yxatdan o'tkazish (marshrut / alone /
  /// intercity uchun universal).
  ///
  /// Atomic flow:
  ///   1. Bugungi (driverId + taxiType + date) aktiv reyslar `isActive=false`.
  ///   2. Yangi `schedules/{auto}` document.
  ///   3. `queue/{driverId}` set (haydovchi навбатга турадi).
  ///   4. `drivers/{driverId}` update (`isAvailable=true`, todayFrom/To, seats).
  ///
  /// Marshrut uchun [stops] va [direction] talab qilinadi; alone uchun
  /// [startTime]/[endTime]; intercity uchun [price].
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
  }) async {
    final oldSnap = await _col
        .where('driverId', isEqualTo: driverId)
        .where('taxiType', isEqualTo: taxiType)
        .where('date', isEqualTo: date)
        .where('isActive', isEqualTo: true)
        .get();

    final batch = _db.batch();
    for (final d in oldSnap.docs) {
      batch.update(d.reference, {'isActive': false});
    }

    final schedRef = _col.doc();
    final scheduleData = <String, dynamic>{
      'driverId': driverId,
      'driverName': driverName,
      'driverPhone': driverPhone,
      'car': driverCar,
      'plate': driverPlate,
      'taxiType': taxiType,
      'date': date,
      'from': fromText,
      'to': toText,
      'stops': stops,
      'direction': direction,
      'seats': seats,
      'seatsLeft': seats,
      'isActive': true,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (startTime != null) scheduleData['startTime'] = startTime;
    if (endTime != null) scheduleData['endTime'] = endTime;
    if (price != null) scheduleData['price'] = price;
    batch.set(schedRef, scheduleData);

    final queueRef = _db.collection('queue').doc(driverId);
    batch.set(queueRef, {
      'driverId': driverId,
      'driverName': driverName,
      'driverPhone': driverPhone,
      'car': driverCar,
      'plate': driverPlate,
      'taxiType': taxiType,
      'from': fromText,
      'to': toText,
      'stops': stops,
      'scheduleId': schedRef.id,
      'seats': seats,
      'seatsLeft': seats,
      'date': date,
      'onlineAt': FieldValue.serverTimestamp(),
      'isActive': true,
      'expiresAt': Timestamp.fromDate(expiresAt),
    });

    final driverRef = _db.collection('drivers').doc(driverId);
    batch.update(driverRef, {
      'isAvailable': true,
      'todayFrom': fromText,
      'todayTo': toText,
      'seatsLeft': seats,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // intercity haydovchilar uchun intercity_drivers kolleksiyasiga sync
    if (taxiType == 'intercity') {
      final intercityRef = _db.collection('intercity_drivers').doc(driverId);
      int hour = 8;
      if (startTime != null && startTime.contains(':')) {
        hour = int.tryParse(startTime.split(':')[0]) ?? 8;
      }
      batch.set(intercityRef, {
        'name': driverName,
        'phone': driverPhone,
        'plate': driverPlate,
        'seats': seats,
        'price': price ?? 0,
        'hour': hour,
        'isActive': true,
        'parcel': false,
        'rating': 4.5,
        'from': fromText,
        'to': toText,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
    return schedRef.id;
  }
}

