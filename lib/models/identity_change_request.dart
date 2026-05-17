import 'package:cloud_firestore/cloud_firestore.dart';

class BirthDateChangeRequest {
  const BirthDateChangeRequest({
    required this.id,
    required this.userId,
    required this.currentBirthDate,
    required this.requestedBirthDate,
    required this.status,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String currentBirthDate;
  final String requestedBirthDate;
  final String status;
  final DateTime? createdAt;

  factory BirthDateChangeRequest.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    return BirthDateChangeRequest(
      id: doc.id,
      userId: (d['userId'] ?? '') as String,
      currentBirthDate: (d['currentBirthDate'] ?? '') as String,
      requestedBirthDate: (d['requestedBirthDate'] ?? '') as String,
      status: (d['status'] ?? 'pending') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class DeviceChangeRequest {
  const DeviceChangeRequest({
    required this.id,
    required this.deviceId,
    required this.currentUserId,
    required this.currentPhone,
    required this.requestedUserId,
    required this.requestedPhone,
    required this.reason,
    required this.status,
    this.signalKey = '',
    this.signals = const <String, dynamic>{},
    this.createdAt,
  });

  final String id;
  final String deviceId;
  final String currentUserId;
  final String currentPhone;
  final String requestedUserId;
  final String requestedPhone;
  final String reason;
  final String status;
  final String signalKey;
  final Map<String, dynamic> signals;
  final DateTime? createdAt;

  factory DeviceChangeRequest.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    final rawSignals = d['signals'];
    return DeviceChangeRequest(
      id: doc.id,
      deviceId: (d['deviceId'] ?? '') as String,
      currentUserId: (d['currentUserId'] ?? '') as String,
      currentPhone: (d['currentPhone'] ?? '') as String,
      requestedUserId: (d['requestedUserId'] ?? '') as String,
      requestedPhone: (d['requestedPhone'] ?? '') as String,
      reason: (d['reason'] ?? '') as String,
      status: (d['status'] ?? 'pending') as String,
      signalKey: (d['signalKey'] ?? '') as String,
      signals: rawSignals is Map<String, dynamic>
          ? rawSignals
          : (rawSignals is Map
              ? Map<String, dynamic>.from(rawSignals)
              : const <String, dynamic>{}),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
