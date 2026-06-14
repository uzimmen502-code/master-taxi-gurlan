import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../utils/intercity_places.dart';

/// Бронь ҳолатлари. Иккита терминал ҳолат — `completed` ва `cancelled`/`expired`.
class IntercityBookingStatus {
  IntercityBookingStatus._();

  /// Бронь яратилди, ҳайдовчи ҳали тасдиқламаган.
  static const String pending = 'pending';

  /// Ҳайдовчи бронни тасдиқлади / auto-confirmed.
  static const String confirmed = 'confirmed';

  /// Сафар бажарилди.
  static const String completed = 'completed';

  /// Мижоз ёки ҳайдовчи бекор қилди.
  static const String cancelled = 'cancelled';

  /// Тасдиқланмай муддати ўтиб кетди.
  static const String expired = 'expired';

  /// "Тирик" ҳолатлар — бекор қилиш мумкин, мижозга кўрсатилади.
  static const Set<String> active = {pending, confirmed};
}

/// `intercity_bookings/{bookingId}` hujjati.
///
/// Шаҳарлараро такси учун **ишончли бронь** — реал Firestore ёзуви:
///   - тариfic-тариfic seat reservation (transactional)
///   - status machine (pending → confirmed → completed / cancelled)
///   - ҳар bron `driver+client` aggregation (`intercity_drivers/{id}/clients/{phone}`)
///     учун manba — "доимий мижоз" базаси шу ердан қурилади.
class IntercityBooking {
  const IntercityBooking({
    required this.id,
    required this.userPhone,
    required this.userName,
    required this.driverId,
    required this.driverPhone,
    required this.driverName,
    required this.carNumber,
    required this.fromCity,
    required this.toCity,
    required this.district,
    required this.passengers,
    required this.pricePerSeat,
    required this.totalAmount,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    required this.departureTime,
    this.userGender = '',
    this.userBirthDate = '',
    this.confirmedAt,
    this.completedAt,
    this.cancelledAt,
    this.cancelReason,
    this.pickupAddress = '',
    this.pickupLat,
    this.pickupLng,
    this.dropoffNote = '',
    this.archivedByDriver = false,
    this.pickedUp = false,
    this.passengerRating,
    this.driverRouteLabel = '',
  });

  final String id;
  final String userPhone;
  final String userName;
  final String driverId;
  final String driverPhone;
  final String driverName;
  final String carNumber;
  final String fromCity;
  final String toCity;
  final String district;
  final int passengers;
  final int pricePerSeat;
  final int totalAmount;
  final String status;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime departureTime;
  /// Брон яратilganda профил snapshot (boshqa yo'lovchilar o'qishi uchun).
  final String userGender;
  final String userBirthDate;
  final DateTime? confirmedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final String pickupAddress;
  final double? pickupLat;
  final double? pickupLng;
  final String dropoffNote;
  final bool archivedByDriver;
  final bool pickedUp;
  final int? passengerRating;
  /// Haydovchi to'liq marshruti (Firestore `routeLabel` snapshot).
  final String driverRouteLabel;

  bool get isActive => IntercityBookingStatus.active.contains(status);
  bool get hasPickupAddress => pickupAddress.trim().isNotEmpty;
  bool get hasPickupGps => pickupLat != null && pickupLng != null;
  bool get isCancellable => isActive;

  /// `bookingId` нинг охирги 6 та белгиси — мижозга кўрсатиш учун қисқа реф.
  String get shortRef =>
      id.length > 6 ? id.substring(id.length - 6).toUpperCase() : id.toUpperCase();

  /// Маршрут қисқача: "Хоразм → Тoshкент" (ichki / fallback).
  String get routeShort {
    final to = district.isNotEmpty ? '$toCity • $district' : toCity;
    return '$fromCity → $to';
  }

  /// UI: haydovchi to'liq marshruti qisqa ko'rinishda.
  String routeDisplayLabel(Locale locale) {
    if (driverRouteLabel.trim().isNotEmpty) {
      return IntercityPlaces.shortRouteLabel(driverRouteLabel, locale: locale);
    }
    return IntercityPlaces.shortRouteLabel(routeShort, locale: locale);
  }

  factory IntercityBooking.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    DateTime ts(String k, {DateTime? fallback}) {
      final v = d[k];
      if (v is Timestamp) return v.toDate();
      return fallback ?? DateTime.now();
    }

    DateTime? tsOpt(String k) {
      final v = d[k];
      if (v is Timestamp) return v.toDate();
      return null;
    }

    return IntercityBooking(
      id: doc.id,
      userPhone: (d['userPhone'] ?? '') as String,
      userName: (d['userName'] ?? '') as String,
      driverId: (d['driverId'] ?? '') as String,
      driverPhone: (d['driverPhone'] ?? '') as String,
      driverName: (d['driverName'] ?? '') as String,
      carNumber: (d['carNumber'] ?? '') as String,
      fromCity: (d['fromCity'] ?? '') as String,
      toCity: (d['toCity'] ?? '') as String,
      district: (d['district'] ?? '') as String,
      passengers: (d['passengers'] as num?)?.toInt() ?? 1,
      pricePerSeat: (d['pricePerSeat'] as num?)?.toInt() ?? 0,
      totalAmount: (d['totalAmount'] as num?)?.toInt() ?? 0,
      status: (d['status'] ?? IntercityBookingStatus.pending) as String,
      createdAt: ts('createdAt'),
      expiresAt: ts('expiresAt',
          fallback: DateTime.now().add(const Duration(minutes: 30))),
      departureTime: ts('departureTime'),
      userGender: (d['userGender'] ?? '') as String,
      userBirthDate: (d['userBirthDate'] ?? '') as String,
      confirmedAt: tsOpt('confirmedAt'),
      completedAt: tsOpt('completedAt'),
      cancelledAt: tsOpt('cancelledAt'),
      cancelReason: d['cancelReason'] as String?,
      pickupAddress: (d['pickupAddress'] ?? '') as String,
      pickupLat: (d['pickupLat'] as num?)?.toDouble(),
      pickupLng: (d['pickupLng'] as num?)?.toDouble(),
      dropoffNote: (d['dropoffNote'] ?? '') as String,
      archivedByDriver: (d['archivedByDriver'] ?? false) as bool,
      pickedUp: (d['pickedUp'] as bool?) ?? false,
      passengerRating: (d['passengerRating'] as num?)?.toInt(),
      driverRouteLabel: (d['driverRouteLabel'] ?? '') as String,
    );
  }
}
