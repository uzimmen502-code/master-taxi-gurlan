import 'package:cloud_firestore/cloud_firestore.dart';

/// `users/{uid}/driverProfiles/marshrut` hujjati — marshrut haydovchi
/// uchun ro'yxatdan o'tgan ma'lumotlar.
class MarshrutDriverProfile {
  const MarshrutDriverProfile({
    required this.uid,
    this.driverName = '',
    this.driverPhone = '',
    this.carModel = '',
    this.plate = '',
    this.seats = 4,
    this.stops = const [],
    this.startTime = '07:00',
  });

  final String uid;
  final String driverName;
  final String driverPhone;
  final String carModel;
  final String plate;
  final int seats;
  final List<String> stops;
  final String startTime;

  factory MarshrutDriverProfile.fromDoc(
    String uid,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    return MarshrutDriverProfile(
      uid: uid,
      driverName: (d['driverName'] ?? '') as String,
      driverPhone: (d['driverPhone'] ?? '') as String,
      carModel: (d['carModel'] ?? '') as String,
      plate: (d['plate'] ?? '') as String,
      seats: (d['seats'] as num?)?.toInt() ?? 4,
      stops: List<String>.from(d['stops'] ?? const []),
      startTime: (d['startTime'] ?? '07:00') as String,
    );
  }

  /// `users/{uid}/driverProfiles/marshrut` ga yozish uchun payload.
  Map<String, dynamic> toProfileMap() => {
        'carModel': carModel,
        'plate': plate,
        'seats': seats,
        'stops': stops,
        'startTime': startTime,
        'driverName': driverName,
        'driverPhone': driverPhone,
      };
}
