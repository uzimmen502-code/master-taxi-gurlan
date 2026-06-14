import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/formatters.dart';
import '../models/collection_task.dart';

/// `collection_tasks` — йiғib оlish vazifalari (faqat o'qish; yaratish CF orqali).
class CollectionTasksRepository {
  CollectionTasksRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const _activeStatuses = ['assigned', 'collecting'];

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('collection_tasks');

  Stream<List<CollectionTask>> watchForCourier(String courierUid) {
    final uid = phoneDigits(courierUid);
    if (uid.length < 9) return Stream.value(const []);
    return _col
        .where('courierId', isEqualTo: uid)
        .where('status', whereIn: _activeStatuses)
        .snapshots()
        .map((s) => s.docs.map(CollectionTask.fromDoc).toList(growable: false));
  }

  Stream<List<CollectionTask>> watchAllActive() {
    return _col
        .where('status', whereIn: _activeStatuses)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(CollectionTask.fromDoc).toList(growable: false));
  }

  Future<CollectionTask?> getById(String id) async {
    if (id.isEmpty) return null;
    final snap = await _col.doc(id).get();
    if (!snap.exists) return null;
    return CollectionTask.fromDoc(snap);
  }
}
