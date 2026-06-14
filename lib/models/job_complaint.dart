import 'package:cloud_firestore/cloud_firestore.dart';

/// `complaints` — ИШ ТОП эълонига шикоят.
class JobComplaint {
  const JobComplaint({
    required this.id,
    required this.adId,
    required this.reason,
    this.reporterPhone = '',
    this.createdAt,
  });

  final String id;
  final String adId;
  final String reason;
  final String reporterPhone;
  final DateTime? createdAt;

  factory JobComplaint.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return JobComplaint(
      id: doc.id,
      adId: (d['adId'] ?? '') as String,
      reason: (d['reason'] ?? '') as String,
      reporterPhone: (d['reporterPhone'] ?? '') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
