import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../utils/intercity_places.dart';

/// `intercity_drivers/{id}` hujjati асосида қурилган view-model. Firestore
/// faqat haydovchining shaxsiy ma'lumotlarini saqlaydi; `fromCity`/`toCity`/
/// `district`/`departureTime` qiymatlari foydalanuvchi tanlovi va sana asosida
/// то'ldiriladi.
class IntercityRide {
  const IntercityRide({
    required this.id,
    required this.driverName,
    required this.rating,
    required this.carModel,
    required this.carNumber,
    required this.phoneNumber,
    required this.price,
    required this.availableSeats,
    required this.fromCity,
    required this.toCity,
    required this.district,
    required this.departureTime,
    this.stops = const [],
    this.routeLabel = '',
    this.driverFrom = '',
    this.driverTo = '',
    this.maleCount = 0,
    this.femaleCount = 0,
  });

  final String id;
  final String driverName;
  final double rating;
  final String carModel;
  final String carNumber;
  final String phoneNumber;
  final int price;
  final int availableSeats;
  final String fromCity;
  final String toCity;
  final String district;
  final DateTime departureTime;
  final List<String> stops;
  final String routeLabel;
  final String driverFrom;
  final String driverTo;
  final int maleCount;
  final int femaleCount;

  List<String> get routeStops {
    if (stops.length >= 2) return stops;
    if (driverFrom.isNotEmpty && driverTo.isNotEmpty) {
      return [driverFrom, driverTo];
    }
    return stops;
  }

  String get carDisplay {
    if (carModel.isNotEmpty && carNumber.isNotEmpty) {
      return '$carModel · $carNumber';
    }
    return carModel.isNotEmpty ? carModel : carNumber;
  }

  String routeDisplayLabel(Locale locale) => IntercityPlaces.rideRouteDisplay(
        routeLabel: routeLabel,
        stops: stops,
        driverFrom: driverFrom,
        driverTo: driverTo,
        locale: locale,
      );

  IntercityRide copyWith({
    int? availableSeats,
    int? maleCount,
    int? femaleCount,
  }) {
    return IntercityRide(
      id: id,
      driverName: driverName,
      rating: rating,
      carModel: carModel,
      carNumber: carNumber,
      phoneNumber: phoneNumber,
      price: price,
      availableSeats: availableSeats ?? this.availableSeats,
      fromCity: fromCity,
      toCity: toCity,
      district: district,
      departureTime: departureTime,
      stops: stops,
      routeLabel: routeLabel,
      driverFrom: driverFrom,
      driverTo: driverTo,
      maleCount: maleCount ?? this.maleCount,
      femaleCount: femaleCount ?? this.femaleCount,
    );
  }

  factory IntercityRide.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc, {
    required String fromCity,
    required String toCity,
    required String district,
    required DateTime baseDate,
  }) {
    final d = doc.data() ?? const <String, dynamic>{};
    final hour = (d['hour'] as num?)?.toInt() ?? 8;
    final rawStops = d['stops'];
    final stops = rawStops is List
        ? rawStops.map((e) => e.toString()).toList(growable: false)
        : const <String>[];
    return IntercityRide(
      id: doc.id,
      driverName: (d['name'] ?? '') as String,
      rating: ((d['avgRating'] ?? d['rating']) as num?)?.toDouble() ?? 0.0,
      carModel: (d['car'] ?? '') as String,
      carNumber: (d['plate'] ?? '') as String,
      phoneNumber: (d['phone'] ?? '') as String,
      price: (d['price'] as num?)?.toInt() ?? 0,
      availableSeats: (d['seats'] as num?)?.toInt() ?? 4,
      fromCity: fromCity,
      toCity: toCity,
      district: district,
      departureTime:
          DateTime(baseDate.year, baseDate.month, baseDate.day, hour),
      stops: stops,
      routeLabel: (d['routeLabel'] ?? '') as String,
      driverFrom: (d['from'] ?? '') as String,
      driverTo: (d['to'] ?? '') as String,
      maleCount: (d['maleCount'] as num?)?.toInt() ?? 0,
      femaleCount: (d['femaleCount'] as num?)?.toInt() ?? 0,
    );
  }
}
