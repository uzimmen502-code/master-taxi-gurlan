import 'package:cloud_firestore/cloud_firestore.dart';

import 'sell_offer_item.dart';
import 'user_address.dart';

/// `sell_submissions` — фoydalanuvchi sotish takliflari (bir yuborishda bir nechta mahsulot).
class SellSubmission {
  const SellSubmission({
    required this.id,
    required this.userId,
    required this.userPhone,
    required this.userName,
    required this.items,
    required this.status,
    required this.createdAt,
    this.visibleToUserIds = const [],
    this.adminNote = '',
    this.forwardAudience = '',
    this.pickupAddress = '',
    this.pickupLat,
    this.pickupLng,
    this.pickupNote = '',
    this.collectionTaskId = '',
    this.inCollection = false,
  });

  final String id;
  final String userId;
  final String userPhone;
  final String userName;
  final List<SellOfferItem> items;

  /// `pending` | `reviewed` | `archived`
  final String status;
  final DateTime createdAt;

  /// Келажакда админ бошқа фoydalanuvchilarga йўnalтириш учун.
  final List<String> visibleToUserIds;
  final String adminNote;
  final String forwardAudience;

  /// Курьер учун — тўliq манzil матни.
  final String pickupAddress;

  /// GPS координаталари (курьер / xarita).
  final double? pickupLat;
  final double? pickupLng;

  /// Қўshimcha ориентир (подъезд, қават).
  final String pickupNote;

  /// Йиғиб олиш вазифаси (`collection_tasks/{id}`), бўш — ҳали йўқ.
  final String collectionTaskId;
  final bool inCollection;

  bool get hasPickupGps => pickupLat != null && pickupLng != null;

  bool get isForwarded => forwardAudience.isNotEmpty;

  String get forwardAudienceLabel {
    switch (forwardAudience) {
      case 'all':
        return 'Барчага';
      case 'selected':
        return 'Танланганлар';
      default:
        return '';
    }
  }

  String? get mapsUrl {
    if (!hasPickupGps) return null;
    return 'https://www.google.com/maps?q=$pickupLat,$pickupLng';
  }

  factory SellSubmission.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final rawItems = d['items'];
    final items = <SellOfferItem>[];
    if (rawItems is List) {
      for (final e in rawItems) {
        if (e is Map) {
          items.add(SellOfferItem.fromMap(Map<String, dynamic>.from(e)));
        }
      }
    }
    final vis = d['visibleToUserIds'];
    final visible = <String>[];
    if (vis is List) {
      for (final v in vis) {
        if (v is String && v.isNotEmpty) visible.add(v);
      }
    }

    final details = d['pickupDetails'];
    var note = '';
    if (details is Map) {
      note = (details['note'] ?? '') as String;
    }

    return SellSubmission(
      id: doc.id,
      userId: (d['userId'] ?? '') as String,
      userPhone: (d['userPhone'] ?? '') as String,
      userName: (d['userName'] ?? '') as String,
      items: items,
      status: (d['status'] ?? 'pending') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      visibleToUserIds: visible,
      adminNote: (d['adminNote'] ?? '') as String,
      forwardAudience: (d['forwardAudience'] ?? '') as String,
      pickupAddress: (d['pickupAddress'] ?? '') as String,
      pickupLat: (d['pickupLat'] as num?)?.toDouble(),
      pickupLng: (d['pickupLng'] as num?)?.toDouble(),
      pickupNote: note,
      collectionTaskId: (d['collectionTaskId'] ?? '') as String,
      inCollection: d['inCollection'] == true,
    );
  }

  static Map<String, dynamic> pickupFieldsFromAddress({
    required UserAddress address,
    String legacy = '',
  }) {
    final parts = <String>[];
    if (address.formatted.isNotEmpty) {
      parts.add(address.formatted);
    } else if (legacy.trim().isNotEmpty) {
      parts.add(legacy.trim());
    }
    if (address.note.trim().isNotEmpty) {
      parts.add(address.note.trim());
    }

    return {
      'pickupAddress': parts.join(', '),
      if (address.lat != null) 'pickupLat': address.lat,
      if (address.lng != null) 'pickupLng': address.lng,
      'pickupDetails': {
        'mfy': address.mfy,
        'street': address.street,
        'house': address.house,
        'district': address.district,
        'note': address.note,
        if (address.lat != null) 'lat': address.lat,
        if (address.lng != null) 'lng': address.lng,
      },
    };
  }

  Map<String, dynamic> toCreateMap() {
    final map = <String, dynamic>{
      'userId': userId,
      'userPhone': userPhone,
      'userName': userName,
      'items': items.map((e) => e.toMap()).toList(),
      'status': 'pending',
      'visibleToUserIds': <String>[],
      'adminNote': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (pickupAddress.isNotEmpty) map['pickupAddress'] = pickupAddress;
    if (pickupLat != null) map['pickupLat'] = pickupLat;
    if (pickupLng != null) map['pickupLng'] = pickupLng;
    if (pickupNote.isNotEmpty) {
      map['pickupDetails'] = {'note': pickupNote};
    }
    return map;
  }

  Map<String, dynamic> toCreateMapWithPickup(Map<String, dynamic> pickup) {
    return {...toCreateMap(), ...pickup};
  }

  static String statusLabel(String s) {
    switch (s) {
      case 'reviewed':
        return 'Кўрилди';
      case 'archived':
        return 'Архив';
      default:
        return 'Янги';
    }
  }
}
