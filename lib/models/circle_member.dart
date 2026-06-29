import 'package:cloud_firestore/cloud_firestore.dart';

/// `circles/{circleId}/members/{userId}` — userId = `canonicalPhoneId` (998...).
///
/// Maxfiylik: telefon DEFAULT yashirin. `phoneVisible=false` bo'lsa `phone`
/// umuman yozilmaydi (faqat egasining shaxsiy profilida qoladi). Egasi
/// "ko'rsatish"ni yoqsa, repository telefonni shu hujjatga yozadi.
class CircleMember {
  const CircleMember({
    required this.userId,
    required this.fullName,
    this.role = 'member',
    this.status = 'active',
    this.photoPath = '',
    this.classLabel = '',
    this.currentCity = '',
    this.currentJob = '',
    this.subgroupId,
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
  final String classLabel;
  final String currentCity;
  final String currentJob;
  final String? subgroupId;

  /// Faqat phoneVisible=true bo'lsa to'ldiriladi.
  final String phone;
  final bool phoneVisible;

  bool get isOwner => role == 'owner';

  factory CircleMember.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return CircleMember(
      userId: doc.id,
      fullName: (d['fullName'] ?? '') as String,
      role: (d['role'] ?? 'member') as String,
      status: (d['status'] ?? 'active') as String,
      photoPath: (d['photoPath'] ?? '') as String,
      classLabel: (d['classLabel'] ?? '') as String,
      currentCity: (d['currentCity'] ?? '') as String,
      currentJob: (d['currentJob'] ?? '') as String,
      subgroupId: d['subgroupId'] as String?,
      phone: (d['phone'] ?? '') as String,
      phoneVisible: d['phoneVisible'] == true,
    );
  }

  /// Members hujjatiga yoziladigan maydonlar. Telefon faqat ko'rinadigan
  /// bo'lsa kiritiladi (maxfiylik).
  Map<String, dynamic> toWriteMap({String? overrideRole}) {
    return {
      'userId': userId,
      'fullName': fullName,
      'role': overrideRole ?? role,
      'status': status,
      'photoPath': photoPath,
      'classLabel': classLabel,
      'currentCity': currentCity,
      'currentJob': currentJob,
      if (subgroupId != null) 'subgroupId': subgroupId,
      'phoneVisible': phoneVisible,
      'phone': phoneVisible ? phone : '',
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
