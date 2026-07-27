import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/relative_person.dart';
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

  /// Фақат берилган id лар учун redirect (бутун коллекция эмас).
  Future<Map<String, String>> fetchRedirectsForIds(Iterable<String> ids) async {
    final result = <String, String>{};
    var pending = ids.where((id) => id.isNotEmpty).toSet();
    const maxHops = 8;
    const batchSize = 100;

    for (var hop = 0; hop < maxHops && pending.isNotEmpty; hop++) {
      final chunk = pending.toList(growable: false);
      pending = <String>{};
      for (var i = 0; i < chunk.length; i += batchSize) {
        final end =
            (i + batchSize < chunk.length) ? i + batchSize : chunk.length;
        final slice = chunk.sublist(i, end);
        final snaps = await Future.wait(
          slice.map(
            (id) => _db.collection('tree_redirects').doc(id).get(),
          ),
        );
        for (final s in snaps) {
          if (!s.exists) continue;
          final data = s.data();
          if (data == null) continue;
          final to = (data['to'] ?? '').toString();
          if (to.isEmpty) continue;
          result[s.id] = to;
          if (!result.containsKey(to)) pending.add(to);
        }
      }
    }
    return result;
  }

  /// Personal + component даги барча id ва боғланишлар.
  static Set<String> collectTreeRelatedIds(
    List<RelativePerson> personal,
    List<TreePerson> component,
  ) {
    final ids = <String>{};
    void addLink(String? id) {
      if (id != null && id.isNotEmpty) ids.add(id);
    }

    for (final p in personal) {
      ids.add(p.id);
      addLink(p.fatherId);
      addLink(p.motherId);
      addLink(p.spouseId);
    }
    for (final n in component) {
      ids.add(n.id);
      addLink(n.fatherId);
      addLink(n.motherId);
      addLink(n.spouseId);
    }
    return ids;
  }

  /// Компонент тарихи (audit + undo).
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
