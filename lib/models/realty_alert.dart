import 'package:cloud_firestore/cloud_firestore.dart';

import 'realty_listing.dart';

/// «Шундай уй чиқса, хабар бер» — `realty_alerts/{id}` (эга қарори
/// 2026-10-08). Ёзувни фақат сервер ёзади (`createRealtyAlert`,
/// `setRealtyAlertStatus`); илова фақат ўқийди.
class RealtyAlert {
  const RealtyAlert({
    required this.id,
    required this.deal,
    required this.centerLat,
    required this.centerLng,
    required this.radiusKm,
    required this.status,
    this.roomsMin,
    this.roomsMax,
    this.priceMax,
    this.expiresAt,
    this.createdAt,
  });

  /// Сервердаги `RADIUS_OPTIONS_KM` билан бир хил (`functions/realty_alerts.js`).
  static const radiusOptionsKm = [1, 3, 5, 10];

  final String id;
  final RealtyDeal deal;
  final double centerLat;
  final double centerLng;
  final int radiusKm;

  /// `active` | `paused` | `expired`.
  final String status;
  final int? roomsMin;
  final int? roomsMax;

  /// Бутун сўм; ижарада — ойига.
  final int? priceMax;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  bool get isExpired {
    final e = expiresAt;
    return status == 'expired' || (e != null && e.isBefore(DateTime.now()));
  }

  bool get isActive => status == 'active' && !isExpired;

  factory RealtyAlert.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return RealtyAlert(
      id: doc.id,
      deal: RealtyDealX.parse(d['deal']),
      centerLat: (d['centerLat'] as num?)?.toDouble() ?? 0,
      centerLng: (d['centerLng'] as num?)?.toDouble() ?? 0,
      radiusKm: (d['radiusKm'] as num?)?.toInt() ?? 0,
      status: (d['status'] ?? 'active') as String,
      roomsMin: (d['roomsMin'] as num?)?.toInt(),
      roomsMax: (d['roomsMax'] as num?)?.toInt(),
      priceMax: (d['priceMax'] as num?)?.toInt(),
      expiresAt: _date(d['expiresAt']),
      createdAt: _date(d['createdAt']),
    );
  }
}

/// `users/{uid}/realty_matches/{listingId}` — мос келган эълон (inbox).
/// Фақат очиқ маълумот: рақам, манзил, аниқ нуқта бу ерда ЙЎҚ.
class RealtyMatch {
  const RealtyMatch({
    required this.listingId,
    required this.deal,
    required this.title,
    required this.priceText,
    required this.seen,
    this.rooms,
    this.createdAt,
  });

  final String listingId;
  final RealtyDeal deal;
  final String title;
  final String priceText;
  final bool seen;
  final int? rooms;
  final DateTime? createdAt;

  factory RealtyMatch.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return RealtyMatch(
      listingId: (d['listingId'] ?? doc.id) as String,
      deal: RealtyDealX.parse(d['deal']),
      title: (d['title'] ?? '') as String,
      priceText: (d['priceText'] ?? '') as String,
      seen: d['seen'] == true,
      rooms: (d['rooms'] as num?)?.toInt(),
      createdAt: _date(d['createdAt']),
    );
  }
}

DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : null;
