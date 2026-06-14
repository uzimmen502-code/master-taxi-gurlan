import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/intercity_ride.dart';
import '../utils/intercity_route_match.dart';

/// `intercity_drivers` collection — шаҳарлараро такси haydovchilari.
class IntercityRidesRepository {
  IntercityRidesRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('intercity_drivers');

  static String scheduleDateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  List<IntercityRide> _mapSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap, {
    required String fromCity,
    required String toCity,
    required String passengerFromRaw,
    required String passengerToRaw,
    required String district,
    required DateTime baseDate,
  }) {
    final dateKey = scheduleDateKey(baseDate);
    final todayKey = scheduleDateKey(DateTime.now());

    final rides = snap.docs
        .where((d) {
          final sd = (d.data()['scheduleDate'] as String?)?.trim() ?? '';
          if (sd.isEmpty) return dateKey == todayKey;
          return sd == dateKey;
        })
        .map((d) => IntercityRide.fromDoc(
              d,
              fromCity: fromCity,
              toCity: toCity,
              district: district,
              baseDate: baseDate,
            ))
        .toList(growable: false);

    return rides
        .where((r) => IntercityRouteMatch.matchesSegment(
              driverStops: r.routeStops,
              passengerFrom: passengerFromRaw,
              passengerTo: passengerToRaw,
            ))
        .toList(growable: false);
  }

  /// Бир марта қидирув.
  Future<List<IntercityRide>> getActiveRides({
    required String fromCity,
    required String toCity,
    String? passengerFromRaw,
    String? passengerToRaw,
    required String district,
    required DateTime baseDate,
  }) async {
    final pFrom = passengerFromRaw ?? fromCity;
    final pTo = passengerToRaw ?? toCity;

    try {
      final snap = await _col.where('isActive', isEqualTo: true).get();
      return _mapSnapshot(
        snap,
        fromCity: fromCity,
        toCity: toCity,
        passengerFromRaw: pFrom,
        passengerToRaw: pTo,
        district: district,
        baseDate: baseDate,
      );
    } on FirebaseException catch (e) {
      throw IntercityRidesLoadException(
        e.code == 'permission-denied'
            ? 'Қидирув рухсати йўқ'
            : 'Қидирувда хатолик: ${e.message ?? e.code}',
      );
    } catch (e) {
      throw IntercityRidesLoadException('Қидирувда хатолик: $e');
    }
  }

  /// Real-time — бўш ўринлар брондан кейин ҳам янгиланади.
  Stream<List<IntercityRide>> watchActiveRides({
    required String fromCity,
    required String toCity,
    String? passengerFromRaw,
    String? passengerToRaw,
    required String district,
    required DateTime baseDate,
  }) {
    final pFrom = passengerFromRaw ?? fromCity;
    final pTo = passengerToRaw ?? toCity;

    return _col.where('isActive', isEqualTo: true).snapshots().map((snap) {
      return _mapSnapshot(
        snap,
        fromCity: fromCity,
        toCity: toCity,
        passengerFromRaw: pFrom,
        passengerToRaw: pTo,
        district: district,
        baseDate: baseDate,
      );
    });
  }

  Future<void> startTrip(String driverId) async {
    await _col.doc(driverId).update({
      'tripStatus': 'in_progress',
      'tripStartedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

class IntercityRidesLoadException implements Exception {
  IntercityRidesLoadException(this.message);
  final String message;
  @override
  String toString() => message;
}
