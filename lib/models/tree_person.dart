import 'package:cloud_firestore/cloud_firestore.dart';

import 'relative_person.dart';

/// `tree_persons/{id}` — global nasab grafidagi tugun (ulashiladi).
class TreePerson {
  const TreePerson({
    required this.id,
    required this.fullName,
    this.photoUrl = '',
    this.gender = '',
    this.birthDate,
    this.fatherId,
    this.motherId,
    this.spouseId,
    this.claimedBy,
    this.ownerUid,
    this.componentId = '',
  });

  final String id;
  final String fullName;
  final String photoUrl;
  final String gender;
  final DateTime? birthDate;
  final String? fatherId;
  final String? motherId;
  final String? spouseId;
  final String? claimedBy;
  final String? ownerUid;
  final String componentId;

  bool get isClaimed => (claimedBy ?? '').isNotEmpty;

  factory TreePerson.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return TreePerson(
      id: doc.id,
      fullName: (d['fullName'] ?? '') as String,
      photoUrl: (d['photoUrl'] ?? '') as String,
      gender: (d['gender'] ?? '') as String,
      birthDate: (d['birthDate'] as Timestamp?)?.toDate(),
      fatherId: d['fatherId'] as String?,
      motherId: d['motherId'] as String?,
      spouseId: d['spouseId'] as String?,
      claimedBy: d['claimedBy'] as String?,
      ownerUid: d['ownerUid'] as String?,
      componentId: (d['componentId'] ?? '') as String,
    );
  }

  /// Nasab daraxti vidjeti RelativePerson kutadi — adapter.
  RelativePerson toRelativePerson() => RelativePerson(
        id: id,
        fullName: fullName,
        photoUrl: photoUrl,
        gender: gender,
        birthDate: birthDate,
        fatherId: fatherId,
        motherId: motherId,
        spouseId: spouseId,
      );
}
