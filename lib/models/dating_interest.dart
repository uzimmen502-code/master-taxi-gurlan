import 'package:cloud_firestore/cloud_firestore.dart';

/// `dating_interests/{id}` — qiziqish bildirish (pending/accepted/declined).
class DatingInterest {
  const DatingInterest({
    required this.id,
    required this.fromId,
    required this.toId,
    this.fromName = '',
    this.toName = '',
    this.status = 'pending',
    this.createdAt,
  });

  final String id;
  final String fromId;
  final String toId;
  final String fromName;
  final String toName;
  final String status;
  final DateTime? createdAt;

  factory DatingInterest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return DatingInterest(
      id: doc.id,
      fromId: (d['fromId'] ?? '') as String,
      toId: (d['toId'] ?? '') as String,
      fromName: (d['fromName'] ?? '') as String,
      toName: (d['toName'] ?? '') as String,
      status: (d['status'] ?? 'pending') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
