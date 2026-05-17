import 'package:cloud_firestore/cloud_firestore.dart';

class MarshrutDispatchEvent {
  const MarshrutDispatchEvent({
    required this.id,
    required this.tripId,
    required this.dispatchSessionId,
    required this.type,
    required this.dispatchMode,
    required this.dispatchAttempt,
    required this.dispatchTotal,
    required this.userPhone,
    required this.pickupMfy,
    required this.dropoffMfy,
    required this.driverId,
    required this.driverName,
    required this.driverPhone,
    required this.scheduleId,
    this.offerTimeoutSeconds = 0,
    this.timeoutAutoPauseStreak = 0,
    this.timeoutStreak = 0,
    this.createdAt,
  });

  final String id;
  final String tripId;
  final String dispatchSessionId;
  final String type;
  final String dispatchMode;
  final int dispatchAttempt;
  final int dispatchTotal;
  final String userPhone;
  final String pickupMfy;
  final String dropoffMfy;
  final String driverId;
  final String driverName;
  final String driverPhone;
  final String scheduleId;
  final int offerTimeoutSeconds;
  final int timeoutAutoPauseStreak;
  final int timeoutStreak;
  final DateTime? createdAt;

  factory MarshrutDispatchEvent.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    return MarshrutDispatchEvent(
      id: doc.id,
      tripId: (d['tripId'] ?? '') as String,
      dispatchSessionId: (d['dispatchSessionId'] ?? '') as String,
      type: (d['type'] ?? '') as String,
      dispatchMode: (d['dispatchMode'] ?? 'queue') as String,
      dispatchAttempt: (d['dispatchAttempt'] as num?)?.toInt() ?? 1,
      dispatchTotal: (d['dispatchTotal'] as num?)?.toInt() ?? 1,
      userPhone: (d['userPhone'] ?? '') as String,
      pickupMfy: (d['pickupMfy'] ?? '') as String,
      dropoffMfy: (d['dropoffMfy'] ?? '') as String,
      driverId: (d['driverId'] ?? '') as String,
      driverName: (d['driverName'] ?? '') as String,
      driverPhone: (d['driverPhone'] ?? '') as String,
      scheduleId: (d['scheduleId'] ?? '') as String,
      offerTimeoutSeconds:
          (d['offerTimeoutSeconds'] as num?)?.toInt() ?? 0,
      timeoutAutoPauseStreak:
          (d['timeoutAutoPauseStreak'] as num?)?.toInt() ?? 0,
      timeoutStreak: (d['timeoutStreak'] as num?)?.toInt() ?? 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
