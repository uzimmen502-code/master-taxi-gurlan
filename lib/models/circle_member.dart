import 'package:cloud_firestore/cloud_firestore.dart';

/// `circles/{circleId}/members/{userId}` — userId = `canonicalPhoneId` (998...).
///
/// `extra` — tipga xos ixtiyoriy profil maydonlari (classLabel, position, ...).
/// Maxfiylik: telefon DEFAULT yashirin. `phoneVisible=false` bo'lsa `phone`
/// umuman yozilmaydi.
class CircleMember {
  const CircleMember({
    required this.userId,
    required this.fullName,
    this.role = 'member',
    this.status = 'active',
    this.photoPath = '',
    this.extra = const {},
    this.phone = '',
    this.phoneVisible = false,
  });

  final String userId;
  final String fullName;

  /// `owner` | `admin` | `member`.
  final String role;

  /// `active` | `blocked`.
  final String status;

  final String photoPath;

  /// Tipga xos profil qiymatlari (key → value), faqat to'ldirilganlari.
  final Map<String, String> extra;

  /// Faqat phoneVisible=true bo'lsa to'ldiriladi.
  final String phone;
  final bool phoneVisible;

  bool get isOwner => role == 'owner';

  /// Bo'sh bo'lmagan extra qiymatlar (ko'rsatish uchun).
  List<String> get extraValues =>
      extra.values.where((v) => v.trim().isNotEmpty).toList(growable: false);

  factory CircleMember.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final rawExtra = (d['extra'] as Map?) ?? const {};
    return CircleMember(
      userId: doc.id,
      fullName: (d['fullName'] ?? '') as String,
      role: (d['role'] ?? 'member') as String,
      status: (d['status'] ?? 'active') as String,
      photoPath: (d['photoPath'] ?? '') as String,
      extra: rawExtra
          .map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')),
      phone: (d['phone'] ?? '') as String,
      phoneVisible: d['phoneVisible'] == true,
    );
  }

  /// Members hujjatiga yoziladigan maydonlar. Telefon faqat ko'rinadigan
  /// bo'lsa kiritiladi (maxfiylik).
  Map<String, dynamic> toWriteMap({String? overrideRole}) {
    final cleanExtra = <String, String>{};
    extra.forEach((k, v) {
      if (v.trim().isNotEmpty) cleanExtra[k] = v.trim();
    });
    return {
      'userId': userId,
      'fullName': fullName,
      'role': overrideRole ?? role,
      'status': status,
      'photoPath': photoPath,
      'extra': cleanExtra,
      'phoneVisible': phoneVisible,
      'phone': phoneVisible ? phone : '',
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
