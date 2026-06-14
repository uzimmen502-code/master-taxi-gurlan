import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/marshrut_driver_option.dart';
import '../models/queue_entry.dart';
import '../utils/gurlan_places.dart';

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
      list.sort(_compareFairQueue);
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

  /// Marshrut dispatch учун 1-навбат → … → 7-навбат тартиби.
  ///
  /// Queue `onlineAt` бўйича тартибланади; йўналиш, ўрин, active ва expiry
  /// client томонда қайта фильтрланади. Натижа waiting flow'га мос
  /// `MarshrutDriverOption` list.
  Future<List<MarshrutDriverOption>> findNextEligibleMarshrutDrivers({
    required String pickupMfy,
    required String dropoffMfy,
    int limit = 7,
    Set<String> excludeDriverIds = const {},
  }) async {
    final snap = await _col
        .where('taxiType', isEqualTo: 'marshrut')
        .where('isActive', isEqualTo: true)
        .get();
    final candidates = snap.docs.map(QueueEntry.fromDoc).where((q) {
      if (excludeDriverIds.contains(q.driverId)) return false;
      if (q.hasExpired) return false;
      if (!q.isTimeEligible) return false;
      if (q.scheduleId.isEmpty) return false;
      if (!q.routeAllows(
        GurlanPlaces.normalizeMfyName(pickupMfy),
        GurlanPlaces.normalizeMfyName(dropoffMfy),
      )) {
        return false;
      }
      return true;
    }).toList();

    final scheduleSnaps = await Future.wait(
      candidates.map((q) => _schedules.doc(q.scheduleId).get()),
    );

    final queue = <QueueEntry>[];
    for (var i = 0; i < candidates.length; i++) {
      final seats =
          (scheduleSnaps[i].data()?['seatsLeft'] as num?)?.toInt() ?? 0;
      if (seats <= 0) continue;
      queue.add(candidates[i]);
    }
    queue.sort(_compareFairQueue);
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
    final plannedStartAt = data['plannedStartAt'] as Timestamp?;
    final actualOnlineAt = Timestamp.now();
    final queueEligibleAt = plannedStartAt != null &&
            plannedStartAt.toDate().isAfter(DateTime.now())
        ? plannedStartAt
        : actualOnlineAt;

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
      if (plannedStartAt != null) 'plannedStartAt': plannedStartAt,
      'actualOnlineAt': actualOnlineAt,
      'queueEligibleAt': queueEligibleAt,
      'todayTrips': data['todayTrips'] ?? 0,
      'todayRejects': data['todayRejects'] ?? 0,
      'todayTimeouts': data['todayTimeouts'] ?? 0,
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

  int _compareFairQueue(QueueEntry a, QueueEntry b) {
    final byEligible =
        _compareNullableDate(a.queueEligibleAt, b.queueEligibleAt);
    if (byEligible != 0) return byEligible;

    final byTrips = a.todayTrips.compareTo(b.todayTrips);
    if (byTrips != 0) return byTrips;

    final byMisses = a.todayMisses.compareTo(b.todayMisses);
    if (byMisses != 0) return byMisses;

    final byActualOnline =
        _compareNullableDate(a.actualOnlineAt, b.actualOnlineAt);
    if (byActualOnline != 0) return byActualOnline;

    return _compareNullableDate(a.onlineAt, b.onlineAt);
  }

  int _compareNullableDate(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }
}
