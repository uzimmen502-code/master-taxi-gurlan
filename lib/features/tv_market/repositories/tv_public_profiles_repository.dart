import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/utils/formatters.dart';
import '../models/tv_clip.dart';

/// Оммавий жойлаштирувчи исми — `tv_public_profiles/{phone}`.
/// `users` ўқилмайди; роликдаги исм бўш бўлса шу ердан олинади.
class TvPublicProfilesRepository {
  TvPublicProfilesRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('tv_public_profiles');

  Future<void> upsert({required String uid, required String name}) async {
    final id = canonicalPhoneId(uid);
    final display = tvOwnerDisplayName(name);
    if (id.isEmpty || display.isEmpty) return;
    await _col.doc(id).set({
      'name': display,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, String>> fetchMany(Iterable<String> phones) async {
    final ids = phones
        .map(canonicalPhoneId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return const {};
    final out = <String, String>{};
    await Future.wait(ids.map((id) async {
      try {
        final snap = await _col.doc(id).get();
        final n = tvOwnerDisplayName((snap.data()?['name'] ?? '') as String);
        if (n.isNotEmpty) out[id] = n;
      } catch (_) {}
    }));
    final missing = ids.where((id) => !out.containsKey(id)).toList();
    if (missing.isEmpty) return out;
    await Future.wait(missing.map((id) async {
      try {
        final snap = await _db.collection('tv_shops').doc(id).get();
        final n = tvOwnerDisplayName((snap.data()?['name'] ?? '') as String);
        if (n.isNotEmpty) out[id] = n;
      } catch (_) {}
    }));
    return out;
  }
}
