import 'package:cloud_firestore/cloud_firestore.dart';

/// Report sababi — `ev_charging_stations/{stationId}/reports/{reportId}.reason`.
enum EvReportReason {
  wrongLocation,
  stationNotFound,
  notWorking,
  wrongConnector,
  wrongPower,
  wrongPrice,
  other,
}

extension EvReportReasonX on EvReportReason {
  String get key {
    switch (this) {
      case EvReportReason.wrongLocation:
        return 'wrong_location';
      case EvReportReason.stationNotFound:
        return 'station_not_found';
      case EvReportReason.notWorking:
        return 'not_working';
      case EvReportReason.wrongConnector:
        return 'wrong_connector';
      case EvReportReason.wrongPower:
        return 'wrong_power';
      case EvReportReason.wrongPrice:
        return 'wrong_price';
      case EvReportReason.other:
        return 'other';
    }
  }

  String get label {
    switch (this) {
      case EvReportReason.wrongLocation:
        return 'Нотўғри жойлашув';
      case EvReportReason.stationNotFound:
        return 'Нуқта топилмади';
      case EvReportReason.notWorking:
        return 'Ишламайди';
      case EvReportReason.wrongConnector:
        return 'Нотўғри разъём';
      case EvReportReason.wrongPower:
        return 'Нотўғри қувват';
      case EvReportReason.wrongPrice:
        return 'Нотўғри нарх';
      case EvReportReason.other:
        return 'Бошқа';
    }
  }

  static EvReportReason parse(String? key) {
    for (final v in EvReportReason.values) {
      if (v.key == key) return v;
    }
    return EvReportReason.other;
  }
}

/// `ev_charging_stations/{stationId}/reports/{reportId}` — moderatsiya paneli
/// (`admin_web`) uchun o'qiladi.
class EvChargingReport {
  const EvChargingReport({
    required this.id,
    required this.stationId,
    required this.reporterId,
    required this.reason,
    required this.comment,
    required this.resolved,
    this.createdAt,
  });

  final String id;
  final String stationId;
  final String reporterId;
  final EvReportReason reason;
  final String comment;
  final bool resolved;
  final DateTime? createdAt;

  factory EvChargingReport.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
    String stationId,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    return EvChargingReport(
      id: doc.id,
      stationId: stationId,
      reporterId: (d['reporterId'] ?? '') as String,
      reason: EvReportReasonX.parse(d['reason'] as String?),
      comment: (d['comment'] ?? '') as String,
      resolved: d['resolved'] == true,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
