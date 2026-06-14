import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/passenger_cancel_block_rules.dart';
import '../core/utils/formatters.dart';

/// Marshrut yo'lovchi blok qoidalari — [PassengerCancelBlockRules] bilan mos.
typedef MarshrutBlockRules = PassengerCancelBlockRules;

/// `users/{phone}/marshrut_block/state` holati (faqat o'qish + admin tozalash).
typedef MarshrutBlockState = PassengerBlockState;

class MarshrutBlockedUserEntry {
  const MarshrutBlockedUserEntry({
    required this.userId,
    required this.blockedUntil,
    required this.cancelCount,
  });

  final String userId;
  final DateTime blockedUntil;
  final int cancelCount;
}

/// Marshrut blok — faqat o'qish va admin tozalash. Hisoblash CF da.
class MarshrutBlockRepository {
  MarshrutBlockRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _stateRef(String phone) {
    final uid = phoneDigits(phone);
    return _db
        .collection('users')
        .doc(uid)
        .collection('marshrut_block')
        .doc('state');
  }

  Future<MarshrutBlockState> getState(String phone) async {
    if (phoneDigits(phone).isEmpty) {
      return const MarshrutBlockState();
    }
    try {
      final snap = await _stateRef(phone).get();
      if (!snap.exists) return const MarshrutBlockState();
      return _parseDoc(snap.data() ?? {});
    } catch (_) {
      return const MarshrutBlockState();
    }
  }

  /// Real-time blok holati — poll o'rniga `.snapshots()`.
  Stream<MarshrutBlockState> watchState(String phone) {
    if (phoneDigits(phone).isEmpty) {
      return Stream.value(const MarshrutBlockState());
    }
    return _stateRef(phone).snapshots().map((snap) {
      if (!snap.exists) return const MarshrutBlockState();
      return _parseDoc(snap.data() ?? {});
    });
  }

  MarshrutBlockState _parseDoc(Map<String, dynamic> d) {
    return MarshrutBlockState(
      cancelCount: (d['cancelCount'] as num?)?.toInt() ?? 0,
      blockedUntil: (d['blockedUntil'] as Timestamp?)?.toDate(),
      firstCancelAt: (d['firstCancelAt'] as Timestamp?)?.toDate(),
    );
  }

  Future<DateTime?> getBlockedUntil(String phone) async {
    final state = await getState(phone);
    if (!state.isBlocked) return null;
    return state.blockedUntil;
  }

  Future<bool> isBlocked(String phone) async {
    final state = await getState(phone);
    return state.isBlocked;
  }

  /// Admin: blokni va bekor hisoblagichini tozalash.
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
  }

  /// Faol bloklangan foydalanuvchilar (collection group).
  Stream<List<MarshrutBlockedUserEntry>> watchActiveBlocks() {
    final now = Timestamp.now();
    return _db
        .collectionGroup('marshrut_block')
        .where('blockedUntil', isGreaterThan: now)
        .snapshots()
        .map((snap) {
      final list = <MarshrutBlockedUserEntry>[];
      for (final doc in snap.docs) {
        if (doc.id != 'state') continue;
        final userId = doc.reference.parent.parent?.id ?? '';
        if (userId.isEmpty) continue;
        final d = doc.data();
        final until = (d['blockedUntil'] as Timestamp?)?.toDate();
        if (until == null || !until.isAfter(DateTime.now())) continue;
        list.add(MarshrutBlockedUserEntry(
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
