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

  Future<void> upsertPhoto({required String uid, required String photoUrl}) async {
    final id = canonicalPhoneId(uid);
    if (id.isEmpty || photoUrl.trim().isEmpty) return;
    await _col.doc(id).set({
      'photoUrl': photoUrl.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Оммaviy профиль расмлари — топилмаган телефонлар натижада йўқ.
  Future<Map<String, String>> fetchPhotos(Iterable<String> phones) async {
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
        final url = ((snap.data()?['photoUrl'] ?? '') as String).trim();
        if (url.isNotEmpty) out[id] = url;
      } catch (_) {}
    }));
    return out;
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

  Future<bool> isFollowing({
    required String viewerId,
    required String targetId,
  }) async {
    final viewer = canonicalPhoneId(viewerId);
    final target = canonicalPhoneId(targetId);
    if (viewer.isEmpty || target.isEmpty) return false;
    try {
      final snap =
          await _col.doc(target).collection('followers').doc(viewer).get();
      return snap.exists;
    } catch (_) {
      return false;
    }
  }

  Future<int> fetchFollowerCount(String targetId) async {
    final id = canonicalPhoneId(targetId);
    if (id.isEmpty) return 0;
    try {
      final snap = await _col.doc(id).get();
      return (snap.data()?['followerCount'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Обуна ёқиш/ўчириш — `followerCount` ±1. Ўзига обуна бўлиш рад этилади.
  Future<bool> toggleFollow({
    required String viewerId,
    required String targetId,
  }) async {
    final viewer = canonicalPhoneId(viewerId);
    final target = canonicalPhoneId(targetId);
    if (viewer.isEmpty || target.isEmpty || viewer == target) return false;
    final targetRef = _col.doc(target);
    final followerRef = targetRef.collection('followers').doc(viewer);
    return _db.runTransaction((tx) async {
      final followerSnap = await tx.get(followerRef);
      final targetSnap = await tx.get(targetRef);
      if (followerSnap.exists) {
        tx.delete(followerRef);
        if (targetSnap.exists) {
          tx.update(targetRef, {'followerCount': FieldValue.increment(-1)});
        }
        return false;
      }
      tx.set(followerRef, {'createdAt': FieldValue.serverTimestamp()});
      if (targetSnap.exists) {
        tx.update(targetRef, {'followerCount': FieldValue.increment(1)});
      }
      return true;
    });
  }

  /// Kanal statistikasi — `totalViewCount` (ixtiyoriy).
  Future<int> fetchTotalViewCount(String phone) async {
    final id = canonicalPhoneId(phone);
    if (id.isEmpty) return 0;
    try {
      final snap = await _col.doc(id).get();
      return (snap.data()?['totalViewCount'] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }
}
