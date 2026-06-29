import 'package:cloud_firestore/cloud_firestore.dart';

/// `tree_history/{id}` — daraxt amallari tarixi (audit + undo).
class TreeHistoryEntry {
  const TreeHistoryEntry({
    required this.id,
    required this.type,
    required this.componentId,
    required this.actorUid,
    required this.summary,
    this.undone = false,
    this.createdAt,
  });

  final String id;
  final String type; // 'link' | 'merge'
  final String componentId;
  final String actorUid;
  final String summary;
  final bool undone;
  final DateTime? createdAt;

  static const _undoable = {'link', 'merge', 'edit', 'create'};

  bool get canUndo => !undone && _undoable.contains(type);

  String get typeLabel {
    switch (type) {
      case 'link':
        return '🔗 Улаш';
      case 'merge':
        return '🔁 Бирлаштириш';
      case 'edit':
        return '✏️ Таҳрир';
      case 'create':
        return '➕ Қўшилди';
      default:
        return type;
    }
  }

  factory TreeHistoryEntry.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return TreeHistoryEntry(
      id: doc.id,
      type: (d['type'] ?? '') as String,
      componentId: (d['componentId'] ?? '') as String,
      actorUid: (d['actorUid'] ?? '') as String,
      summary: (d['summary'] ?? '') as String,
      undone: (d['undone'] ?? false) as bool,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
