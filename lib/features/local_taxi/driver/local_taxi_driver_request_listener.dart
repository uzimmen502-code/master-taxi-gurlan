import 'package:cloud_firestore/cloud_firestore.dart';

class LocalTaxiDriverRequestListener {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<QuerySnapshot> listenRequests() {
    return _db
        .collection('ride_requests')
        .where('status', isEqualTo: 'searching')
        .snapshots();
  }
}