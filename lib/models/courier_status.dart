/// Kuryer real-time holati — `couriers/{uid}` hujjati.
///
/// Hayotiy modeli emas, faqat Firestore'ga yozish uchun payload.
/// O'qish kerak bo'lsa, alohida factory qo'shiladi.
class CourierStatus {
  const CourierStatus({
    required this.uid,
    required this.name,
    required this.phone,
    required this.isOnline,
    this.lat,
    this.lng,
    this.fcmToken = '',
  });

  final String uid;
  final String name;
  final String phone;
  final bool isOnline;
  final double? lat;
  final double? lng;

  /// FCM — `onDeliveryRouteCreate` ва бошқа push учун `couriers/{uid}`да.
  final String fcmToken;

  Map<String, dynamic> toUpsertMap() => {
        'name': name,
        'phone': phone,
        'isOnline': isOnline,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (fcmToken.isNotEmpty) 'fcmToken': fcmToken,
      };
}
