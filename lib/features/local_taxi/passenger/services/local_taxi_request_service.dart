import 'package:cloud_firestore/cloud_firestore.dart';

class LocalTaxiRequestService {
  final _db = FirebaseFirestore.instance;

  Future<void> createRequest({
    required String from,
    String? to,
    required String passengerId,
  }) async {
    await _db.collection('requests').add({
      "from": from,
      "to": to,
      "status": "waiting",
      "passengerId": passengerId,
      "createdAt": FieldValue.serverTimestamp(),
    });
  }
}