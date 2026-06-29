import 'package:cloud_firestore/cloud_firestore.dart';

/// `tree_link_invites/{id}` — daraxt ulash taklifi (taklif → qabul).
class TreeLinkInvite {
  const TreeLinkInvite({
    required this.id,
    required this.fromUid,
    required this.fromName,
    required this.fromNodeId,
    required this.nodeName,
    required this.toUid,
    this.status = 'pending',
    this.createdAt,
  });

  final String id;
  final String fromUid;
  final String fromName;
  final String fromNodeId;
  final String nodeName;
  final String toUid;
  final String status;
  final DateTime? createdAt;

  factory TreeLinkInvite.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return TreeLinkInvite(
      id: doc.id,
      fromUid: (d['fromUid'] ?? '') as String,
      fromName: (d['fromName'] ?? '') as String,
      fromNodeId: (d['fromNodeId'] ?? '') as String,
      nodeName: (d['nodeName'] ?? '') as String,
      toUid: (d['toUid'] ?? '') as String,
      status: (d['status'] ?? 'pending') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
