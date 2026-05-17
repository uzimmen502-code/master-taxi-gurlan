import 'package:cloud_firestore/cloud_firestore.dart';

/// `intercity_drivers/{id}` hujjati асосида қурилган view-model. Firestore
/// faqat haydovchining shaxsiy ma'lumotlarini saqlaydi; `fromCity`/`toCity`/
/// `district`/`departureTime` qiymatlari foydalanuvchi tanlovi va sana asosida
/// то'ldiriladi.
class IntercityRide {
  const IntercityRide({
    required this.id,
    required this.driverName,
    required this.rating,
    required this.carNumber,
    required this.phoneNumber,
    required this.acceptsParcel,
    required this.price,
    required this.availableSeats,
    required this.fromCity,
    required this.toCity,
    required this.district,
    required this.departureTime,
  });

  final String id;
  final String driverName;
  final double rating;
  final String carNumber;
  final String phoneNumber;
  final bool acceptsParcel;
  final int price;
  final int availableSeats;
  final String fromCity;
  final String toCity;
  final String district;
  final DateTime departureTime;

  factory IntercityRide.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required String fromCity,
    required String toCity,
    required String district,
    required DateTime baseDate,
  }) {
    final d = doc.data() ?? const <String, dynamic>{};
    final hour = (d['hour'] as num?)?.toInt() ?? 8;
    return IntercityRide(
      id: doc.id,
      driverName: (d['name'] ?? '') as String,
      rating: (d['rating'] as num?)?.toDouble() ?? 4.0,
      carNumber: (d['plate'] ?? '') as String,
      phoneNumber: (d['phone'] ?? '') as String,
      acceptsParcel: (d['parcel'] ?? false) as bool,
      price: (d['price'] as num?)?.toInt() ?? 0,
      availableSeats: (d['seats'] as num?)?.toInt() ?? 4,
      fromCity: fromCity,
      toCity: toCity,
      district: district,
      departureTime:
          DateTime(baseDate.year, baseDate.month, baseDate.day, hour),
    );
  }
}
