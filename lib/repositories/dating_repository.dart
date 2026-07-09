import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../features/dating/services/dating_service.dart';
import '../models/dating_interest.dart';
import '../models/dating_match.dart';
import '../models/dating_profile.dart';

/// Tanishuv (dating) — Firestore o'qish + chat + blok + shikoyat.
/// Profil/qiziqish/match yozuvlari Cloud Functions orqali (DatingService).
class DatingRepository {
  DatingRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _profiles =>
      _db.collection('dating_profiles');

  Stream<DatingProfile?> watchMyProfile(String uid) {
    return _profiles.doc(uid).snapshots().map(
        (d) => d.exists ? DatingProfile.fromDoc(d) : null);
  }

  Future<DatingProfile?> getProfile(String uid) async {
    final d = await _profiles.doc(uid).get();
    return d.exists ? DatingProfile.fromDoc(d) : null;
  }

  /// Tavsiya — qarama-qarshi jins, tasdiqlangan, faol. Bloklar + o'zini
  /// chiqarib tashlash mijoz tomonida.
  Stream<List<DatingProfile>> watchDiscovery({
    required String myUid,
    required String myGender,
    required Set<String> excludeIds,
    int prefMinAge = 18,
    int prefMaxAge = 80,
  }) {
    final minAge = prefMinAge.clamp(18, 80);
    final maxAge = prefMaxAge.clamp(18, 80);
    final lo = math.min(minAge, maxAge);
    final hi = math.max(minAge, maxAge);
    final oppositeGender = myGender == 'male' ? 'female' : 'male';
    return _profiles
        .where('gender', isEqualTo: oppositeGender)
        .where('status', isEqualTo: 'approved')
        .where('active', isEqualTo: true)
        .orderBy('lastActive', descending: true)
        .limit(100)
        .snapshots()
        .map((s) => s.docs
            .map(DatingProfile.fromDoc)
            .where((p) {
              if (p.userId == myUid || excludeIds.contains(p.userId)) {
                return false;
              }
              final age = p.age;
              if (age == null) return false;
              return age >= lo && age <= hi;
            })
            .toList(growable: false));
  }

  // ── Bloklash ──────────────────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> _blockList(String uid) =>
      _db.collection('dating_blocks').doc(uid).collection('list');

  Stream<Set<String>> watchBlockedIds(String uid) {
    return _blockList(uid)
        .snapshots()
        .map((s) => s.docs.map((d) => d.id).toSet());
  }

  Future<void> block(String uid, String targetId) async {
    await _blockList(uid).doc(targetId).set({
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> unblock(String uid, String targetId) async {
    await _blockList(uid).doc(targetId).delete();
  }

  // ── Qiziqishlar ───────────────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> get _interests =>
      _db.collection('dating_interests');

  Stream<List<DatingInterest>> watchIncomingInterests(String uid) {
    return _interests
        .where('toId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(DatingInterest.fromDoc).toList(growable: false));
  }

  Stream<List<DatingInterest>> watchSentInterests(String uid) {
    return _interests
        .where('fromId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((s) => s.docs.map(DatingInterest.fromDoc).toList(growable: false));
  }

  // ── Match + chat ──────────────────────────────────────────────────
  CollectionReference<Map<String, dynamic>> get _matches =>
      _db.collection('dating_matches');

  Stream<List<DatingMatch>> watchMatches(String uid) {
    return _matches
        .where('users', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(DatingMatch.fromDoc).toList(growable: false));
  }

  Stream<List<DatingMessage>> watchMessages(String matchId) {
    return _matches
        .doc(matchId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .limit(500)
        .snapshots()
        .map((s) => s.docs.map(DatingMessage.fromDoc).toList(growable: false));
  }

  Future<void> sendMessage({
    required String matchId,
    required String senderId,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final batch = _db.batch();
    final msgRef = _matches.doc(matchId).collection('messages').doc();
    batch.set(msgRef, {
      'senderId': senderId,
      'text': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_matches.doc(matchId), {
      'lastMessage': trimmed.length > 120 ? trimmed.substring(0, 120) : trimmed,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  // ── Shikoyat ──────────────────────────────────────────────────────
  Future<void> report({
    required String reporterId,
    required String targetId,
    required String reason,
  }) async {
    await DatingService.submitReport(targetId: targetId, reason: reason);
  }

  // ── Admin moderatsiya o'qishlari ──────────────────────────────────
  Stream<List<DatingProfile>> watchByStatus(String status) {
    return _profiles
        .where('status', isEqualTo: status)
        .limit(200)
        .snapshots()
        .map((s) => s.docs.map(DatingProfile.fromDoc).toList(growable: false));
  }
}
