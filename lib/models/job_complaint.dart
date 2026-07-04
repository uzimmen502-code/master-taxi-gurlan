import 'package:cloud_firestore/cloud_firestore.dart';

/// `complaints` — ИШ ТОП эълонига шикoyat.
class JobComplaint {
  const JobComplaint({
    required this.id,
    required this.adId,
    required this.reason,
    this.reporterPhone = '',
    this.createdAt,
    this.resolved = false,
    this.resolvedAt,
    this.resolvedBy = '',
  });

  final String id;
  final String adId;
  final String reason;
  final String reporterPhone;
  final DateTime? createdAt;
  final bool resolved;
  final DateTime? resolvedAt;
  final String resolvedBy;

  factory JobComplaint.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return JobComplaint(
      id: doc.id,
      adId: (d['adId'] ?? '') as String,
      reason: (d['reason'] ?? '') as String,
      reporterPhone: (d['reporterPhone'] ?? '') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      resolved: d['resolved'] == true,
      resolvedAt: (d['resolvedAt'] as Timestamp?)?.toDate(),
      resolvedBy: (d['resolvedBy'] ?? '') as String,
    );
  }
}
