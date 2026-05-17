import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/intercity_ride.dart';

/// `intercity_drivers` collection — шаҳарлараро такси haydovchilari.
///
/// Hozircha Firestore-da yo'nalish bo'yicha filtirlash yo'q — barcha aktiv
/// haydovchilar olinadi va `IntercityRide` view-model'iga yo'lovchining
/// tanlovi (`fromCity`/`toCity`/...) qo'shiladi.
class IntercityRidesRepository {
  IntercityRidesRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('intercity_drivers');

  /// Барча aktiv reyslar. Хатолик `[]` qaytaradi — caller demo fallback'ga
  /// ўтказа олади.
  Future<List<IntercityRide>> getActiveRides({
    required String fromCity,
    required String toCity,
    required String district,
    required DateTime baseDate,
  }) async {
    try {
      final snap =
          await _col.where('isActive', isEqualTo: true).get();
      return snap.docs
          .map((d) => IntercityRide.fromDoc(
                d,
                fromCity: fromCity,
                toCity: toCity,
                district: district,
                baseDate: baseDate,
              ))
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
