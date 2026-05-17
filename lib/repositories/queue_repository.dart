import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/marshrut_driver_option.dart';
import '../models/queue_entry.dart';

/// `queue` collection — ҳайдовчи навбати.
///
/// Маршрут-специфик `MarshrutDriverRepository.watchQueuePosition` фақат
/// позицияни қайтаради. Бу repository эса бутун навбат рўйхатини ва
/// CRUD амалларни тақдим этади.
class QueueRepository {
  QueueRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('queue');
  CollectionReference<Map<String, dynamic>> get _schedules =>
      _db.collection('schedules');

  /// Берилган taxi турига оид актив навбатни кузатиш —
  /// `onlineAt` бўйича тартибланган.
  Stream<List<QueueEntry>> watchByType(String taxiType) {
    return _col
        .where('taxiType', isEqualTo: taxiType)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(QueueEntry.fromDoc).toList();
      list.sort((a, b) {
        final at = a.onlineAt;
        final bt = b.onlineAt;
        if (at == null) return 1;
        if (bt == null) return -1;
        return at.compareTo(bt);
      });
      return list;
    });
  }

  /// Dispatch timeout policy auto-paused қилган marshrut ҳайдовчилар.
  Stream<List<QueueEntry>> watchAutoPausedMarshrutDrivers() {
    return _col
        .where('taxiType', isEqualTo: 'marshrut')
        .where('isActive', isEqualTo: false)
        .where('autoPausedReason', isEqualTo: 'dispatch_timeout_streak')
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(QueueEntry.fromDoc).toList();
      list.sort((a, b) => a.driverName.compareTo(b.driverName));
      return list;
    });
  }

  Future<void> reactivateAutoPausedDriver(String driverId) async {
    if (driverId.isEmpty) return;
    await _col.doc(driverId).set({
      'isActive': true,
      'dispatchTimeoutStreak': 0,
      'autoPausedReason': FieldValue.delete(),
      'autoPausedAt': FieldValue.delete(),
      'reactivatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Ҳайдовчини навбатдан чиқариш (логик ўчириш).
  Future<void> leave(String driverId) async {
    if (driverId.isEmpty) return;
    try {
      await _col.doc(driverId).update({'isActive': false});
    } catch (_) {}
  }

  /// Йўловчи қўшилди — `seatsLeft` ни 1 камайтириш. 0 га тушса
  /// `isActive: false` ёзилади.
  Future<void> decrementSeats({
    required String driverId,
    required int currentSeats,
  }) async {
    if (driverId.isEmpty) return;
    if (currentSeats - 1 <= 0) {
      await _col.doc(driverId).update({'isActive': false});
    } else {
      await _col.doc(driverId).update({
        'seatsLeft': FieldValue.increment(-1),
      });
    }
  }

  /// Marshrut dispatch учун 1-навбат → 2-навбат → 3-навбат тартиби.
  ///
  /// Queue `onlineAt` бўйича тартибланади; йўналиш, ўрин, active ва expiry
  /// client томонда қайта фильтрланади. Натижа waiting flow'га мос
  /// `MarshrutDriverOption` list.
  Future<List<MarshrutDriverOption>> findNextEligibleMarshrutDrivers({
    required String pickupMfy,
    required String dropoffMfy,
    int limit = 3,
  }) async {
    final snap = await _col
        .where('taxiType', isEqualTo: 'marshrut')
        .where('isActive', isEqualTo: true)
        .get();
    final queue = snap.docs.map(QueueEntry.fromDoc).where((q) {
      if (q.seatsLeft <= 0) return false;
      if (q.hasExpired) return false;
      if (q.scheduleId.isEmpty) return false;
      if (!q.routeAllows(pickupMfy, dropoffMfy)) return false;
      return true;
    }).toList()
      ..sort((a, b) {
        final at = a.onlineAt;
        final bt = b.onlineAt;
        if (at == null) return 1;
        if (bt == null) return -1;
        return at.compareTo(bt);
      });
    return queue
        .take(limit)
        .map(MarshrutDriverOption.fromQueueEntry)
        .toList(growable: false);
  }

  /// Йўловчи камайди — `seatsLeft` ни 1 ошириш + `isActive: true`.
  Future<void> incrementSeats(String driverId) async {
    if (driverId.isEmpty) return;
    await _col.doc(driverId).set({
      'seatsLeft': FieldValue.increment(1),
      'isActive': true,
    }, SetOptions(merge: true));
  }

  /// Ҳайдовчини навбатга қўшиш. Бугунги аввалги жараёндан позицияни
  /// тиклайди (`last_queue_pos_<driverId>` SharedPreferences калити).
  Future<void> join({
    required String driverId,
    required String driverName,
    required String driverPhone,
    required String car,
    required String plate,
    required String taxiType,
    required String date,
    double? lat,
    double? lng,
  }) async {
    if (driverId.isEmpty) return;
    final sched = await _schedules
        .where('driverId', isEqualTo: driverId)
        .where('date', isEqualTo: date)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();
    if (sched.docs.isEmpty) return;
    final data = sched.docs.first.data();

    final prefs = await SharedPreferences.getInstance();
    final lastPos = prefs.getInt('last_queue_pos_$driverId') ?? 0;
    final lastDate = prefs.getString('last_queue_date_$driverId') ?? '';
    final isReEntry = lastDate == date && lastPos > 0;

    Timestamp onlineAt;
    if (isReEntry) {
      final queueSnap = await _col
          .where('taxiType', isEqualTo: taxiType)
          .where('isActive', isEqualTo: true)
          .get();
      final times = queueSnap.docs
          .map((d) => d.data()['onlineAt'] as Timestamp?)
          .where((t) => t != null)
          .toList()
        ..sort((a, b) => a!.compareTo(b!));
      if (times.length >= lastPos) {
        final ref = times[lastPos - 1]!.toDate();
        onlineAt = Timestamp.fromDate(ref.add(const Duration(seconds: 1)));
      } else {
        onlineAt = Timestamp.now();
      }
    } else {
      onlineAt = Timestamp.now();
    }

    await _col.doc(driverId).set({
      'driverId': driverId,
      'driverName': driverName,
      'driverPhone': driverPhone,
      'car': car,
      'plate': plate,
      'taxiType': taxiType,
      'from': data['from'] ?? '',
      'to': data['to'] ?? '',
      'scheduleId': sched.docs.first.id,
      'seats': data['seats'] ?? 4,
      'seatsLeft': data['seatsLeft'] ?? 4,
      'date': date,
      'onlineAt': onlineAt,
      'isActive': true,
      'lat': lat,
      'lng': lng,
    });

    await prefs.setString('last_queue_date_$driverId', date);
  }

  /// Текущий позицияни SharedPreferences'га ёзиш — кейинги cessión'да
  /// тиклаш учун.
  Future<void> saveLastPosition({
    required String driverId,
    required int position,
  }) async {
    if (driverId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_queue_pos_$driverId', position);
  }

  /// Сессияни тозалаш (иш тугатилди).
  Future<void> clearLastPosition(String driverId) async {
    if (driverId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_queue_pos_$driverId', 0);
    await prefs.setString('last_queue_date_$driverId', '');
  }
}
