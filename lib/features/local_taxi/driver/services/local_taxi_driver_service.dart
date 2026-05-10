import 'package:cloud_firestore/cloud_firestore.dart';

class LocalTaxiDriverService {
  final _db = FirebaseFirestore.instance;

  Future<void> updateDriver({
    required String driverId,
    required String name,
    required String phone,
    required String car,
    required String plate,
    required bool isOnline,
    required bool emptyTaxi,
    double? lat,
    double? lng,
    String? destination,
  }) async {
    await _db.collection('drivers').doc(driverId).set({
      "name": name,
      "phone": phone,
      "car": car,
      "plate": plate,

      "isOnline": isOnline,
      "emptyTaxi": emptyTaxi,

      "lat": lat,
      "lng": lng,

      "destination": destination,

      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}