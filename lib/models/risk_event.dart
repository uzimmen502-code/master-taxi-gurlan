import 'package:cloud_firestore/cloud_firestore.dart';

class RiskEvent {
  const RiskEvent({
    required this.id,
    required this.userId,
    required this.type,
    required this.severity,
    required this.status,
    this.deviceId = '',
    this.message = '',
    this.meta = const <String, dynamic>{},
    this.createdAt,
  });

  final String id;
  final String userId;
  final String type;
  final String severity;
  final String status;
  final String deviceId;
  final String message;
  final Map<String, dynamic> meta;
  final DateTime? createdAt;

  factory RiskEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final rawMeta = d['meta'];
    return RiskEvent(
      id: doc.id,
      userId: (d['userId'] ?? '') as String,
      type: (d['type'] ?? '') as String,
      severity: (d['severity'] ?? 'medium') as String,
      status: (d['status'] ?? 'open') as String,
      deviceId: (d['deviceId'] ?? '') as String,
      message: (d['message'] ?? '') as String,
      meta: rawMeta is Map<String, dynamic>
          ? rawMeta
          : (rawMeta is Map
              ? Map<String, dynamic>.from(rawMeta)
              : const <String, dynamic>{}),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
