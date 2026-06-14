import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/passenger_cancel_block_rules.dart';
import '../core/utils/formatters.dart';

/// Local taxi qidiruv bloki — CF yozadi, client o'qiydi.
class LocalTaxiBlockedUserEntry {
  const LocalTaxiBlockedUserEntry({
    required this.userId,
    required this.blockedUntil,
    required this.cancelCount,
  });

  final String userId;
  final DateTime blockedUntil;
  final int cancelCount;
}

class LocalTaxiBlockRepository {
  LocalTaxiBlockRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _stateRef(String phone) {
    final uid = phoneDigits(phone);
    return _db
        .collection('users')
        .doc(uid)
        .collection('local_taxi_block')
        .doc('state');
  }

  Future<PassengerBlockState> getState(String phone) async {
    if (phoneDigits(phone).isEmpty) return const PassengerBlockState();
    try {
      final snap = await _stateRef(phone).get();
      if (!snap.exists) return const PassengerBlockState();
      final d = snap.data() ?? {};
      return PassengerBlockState(
        cancelCount: (d['cancelCount'] as num?)?.toInt() ?? 0,
        blockedUntil: (d['blockedUntil'] as Timestamp?)?.toDate(),
        firstCancelAt: (d['firstCancelAt'] as Timestamp?)?.toDate(),
      );
    } catch (_) {
      return const PassengerBlockState();
    }
  }

  /// `local_taxi_block/state`; faqat eski APK uchun `users.blockedUntil` fallback.
  Future<DateTime?> getBlockedUntil(String phone) async {
    final state = await getState(phone);
    if (state.isBlocked) return state.blockedUntil;

    final uid = phoneDigits(phone);
    if (uid.isEmpty) return null;
    try {
      final snap = await _db.collection('users').doc(uid).get();
      final ts = snap.data()?['blockedUntil'] as Timestamp?;
      if (ts == null) return null;
      final until = ts.toDate();
      if (!until.isAfter(DateTime.now())) return null;
      return until;
    } catch (_) {
      return null;
    }
  }

  Future<bool> isBlocked(String phone) async {
    final until = await getBlockedUntil(phone);
    return until != null;
  }

  Future<void> clearBlock(String phone) async {
    final uid = phoneDigits(phone);
    if (uid.length < 9) return;
    await _stateRef(phone).set({
      'cancelCount': 0,
      'blockedUntil': FieldValue.delete(),
      'firstCancelAt': FieldValue.delete(),
      'clearedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    try {
      await _db.collection('users').doc(uid).update({
        'blockedUntil': FieldValue.delete(),
        'cancelCount': 0,
      });
    } catch (_) {}
  }

  Stream<List<LocalTaxiBlockedUserEntry>> watchActiveBlocks() {
    final now = Timestamp.now();
    return _db
        .collectionGroup('local_taxi_block')
        .where('blockedUntil', isGreaterThan: now)
        .snapshots()
        .map((snap) {
      final list = <LocalTaxiBlockedUserEntry>[];
      for (final doc in snap.docs) {
        if (doc.id != 'state') continue;
        final userId = doc.reference.parent.parent?.id ?? '';
        if (userId.isEmpty) continue;
        final d = doc.data();
        final until = (d['blockedUntil'] as Timestamp?)?.toDate();
        if (until == null || !until.isAfter(DateTime.now())) continue;
        list.add(LocalTaxiBlockedUserEntry(
          userId: userId,
          blockedUntil: until,
          cancelCount: (d['cancelCount'] as num?)?.toInt() ?? 0,
        ));
      }
      list.sort((a, b) => a.blockedUntil.compareTo(b.blockedUntil));
      return list;
    });
  }
}
