import 'package:cloud_firestore/cloud_firestore.dart';

/// `trips` collection — taksi safari.
///
/// Profile screenda ikki turli "tomon"dan ko'rsatiladi:
///  - haydovchi tomonidan: `userPhone`, `driverName`/`driverCar` bo'sh
///  - foydalanuvchi tomonidan: `driverName`, `driverCar` to'la
class TripModel {
  final String id;
  final String from;
  final String to;
  final int fare;
  final String taxiType;          // alone | marshrut | intercity
  final String userPhone;         // yo'lovchi
  final String driverName;        // qabul qilingan haydovchi
  final String driverCar;
  final DateTime? completedAt;

  const TripModel({
    required this.id,
    this.from = '',
    this.to = '',
    this.fare = 0,
    this.taxiType = 'alone',
    this.userPhone = '',
    this.driverName = '',
    this.driverCar = '',
    this.completedAt,
  });

  factory TripModel.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return TripModel(
      id: doc.id,
      from: d['from'] ?? '',
      to: d['to'] ?? '',
      fare: (d['fare'] as num?)?.toInt() ?? 0,
      taxiType: d['taxiType'] ?? 'alone',
      userPhone: d['userPhone'] ?? '',
      driverName: d['acceptedDriverName'] ?? '',
      driverCar: d['acceptedDriverCar'] ?? '',
      completedAt: (d['completedAt'] as Timestamp?)?.toDate(),
    );
  }
}
