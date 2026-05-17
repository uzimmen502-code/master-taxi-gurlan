import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/trip_model.dart';

/// `trips` collection — yakunlangan taksi safarlari.
class TripsRepository {
  TripsRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('trips');

  /// Haydovchining yakunlangan safarlari.
  Future<List<TripModel>> completedByDriver(
    String driverUid, {
    int limit = 20,
  }) async {
    if (driverUid.isEmpty) return const [];
    final snap = await _col
        .where('acceptedDriverId', isEqualTo: driverUid)
        .where('status', isEqualTo: 'completed')
        .limit(limit)
        .get();
    return _sortByCompletedAt(snap.docs.map(TripModel.fromDoc).toList());
  }

  /// Foydalanuvchining yakunlangan safarlari.
  Future<List<TripModel>> completedByUser(
    List<String> phoneAliases, {
    int limit = 20,
  }) async {
    if (phoneAliases.isEmpty) return const [];
    final snap = await _col
        .where('userPhone', whereIn: phoneAliases)
        .where('status', isEqualTo: 'completed')
        .limit(limit)
        .get();
    return _sortByCompletedAt(snap.docs.map(TripModel.fromDoc).toList());
  }

  List<TripModel> _sortByCompletedAt(List<TripModel> list) {
    list.sort((a, b) {
      final at = a.completedAt;
      final bt = b.completedAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return list;
  }
}
