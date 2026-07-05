import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/tree_history_entry.dart';
import '../models/tree_link_invite.dart';
import '../models/tree_person.dart';

/// Nasab daraxti — global graf o'qishlari (yozish CF orqali: TreeService).
class TreeRepository {
  TreeRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Joriy foydalanuvchining komponent id va "Men" tuguni (users hujjati).
  Stream<({String componentId, String personId})> watchMyTreeMeta(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((d) {
      final m = d.data() ?? const {};
      return (
        componentId: (m['treeComponentId'] ?? '') as String,
        personId: (m['treePersonId'] ?? '') as String,
      );
    });
  }

  /// Komponentdagi barcha tugunlar (ulangan oila tarmog'i).
  Stream<List<TreePerson>> watchComponent(String componentId) {
    if (componentId.isEmpty) {
      return Stream.value(const <TreePerson>[]);
    }
    return _db
        .collection('tree_persons')
        .where('componentId', isEqualTo: componentId)
        .snapshots()
        .map((s) => s.docs.map(TreePerson.fromDoc).toList(growable: false));
  }

  Stream<List<TreeLinkInvite>> watchIncomingInvites(String uid) {
    return _db
        .collection('tree_link_invites')
        .where('toUid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(TreeLinkInvite.fromDoc).toList(growable: false));
  }

  Stream<List<TreeLinkInvite>> watchSentInvites(String uid) {
    return _db
        .collection('tree_link_invites')
        .where('fromUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((s) => s.docs.map(TreeLinkInvite.fromDoc).toList(growable: false));
  }

  /// Merge redirectlari (eski id → yangi id).
  Stream<Map<String, String>> watchRedirects() {
    return _db.collection('tree_redirects').snapshots().map((s) {
      final map = <String, String>{};
      for (final d in s.docs) {
        final to = (d.data()['to'] ?? '') as String;
        if (to.isNotEmpty) map[d.id] = to;
      }
      return map;
    });
  }

  /// Komponent tarixi (audit + undo).
  Stream<List<TreeHistoryEntry>> watchHistory(String componentId) {
    if (componentId.isEmpty) {
      return Stream.value(const <TreeHistoryEntry>[]);
    }
    return _db
        .collection('tree_history')
        .where('componentId', isEqualTo: componentId)
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots()
        .map((s) =>
            s.docs.map(TreeHistoryEntry.fromDoc).toList(growable: false));
  }
}
