import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/courier_status.dart';

/// `couriers` collection — har bir kuryerning online holati va so'nggi GPS.
class CouriersRepository {
  CouriersRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('couriers');

  /// GPS heartbeat — kuryer onlайн bo'lganda har bir lokatsiya yangiланishi.
  Future<void> upsertStatus(CourierStatus s) async {
    if (s.uid.isEmpty) return;
    await _col.doc(s.uid).set({
      ...s.toUpsertMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> goOffline(String uid) async {
    if (uid.isEmpty) return;
    await _col.doc(uid).update({
      'isOnline': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
