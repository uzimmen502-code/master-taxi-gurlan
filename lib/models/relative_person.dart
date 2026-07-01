import 'package:cloud_firestore/cloud_firestore.dart';

/// `relatives/{userId}/people/{personId}` — foydalanuvchining SHAXSIY qarindosh
/// yozuvi (ulashilmaydi). side: 'paternal' (ota tomon) | 'maternal' (ona tomon).
class RelativePerson {
  const RelativePerson({
    required this.id,
    required this.fullName,
    this.photoUrl = '',
    this.photoPath = '',
    this.phone = '',
    this.address = '',
    this.birthDate,
    this.gender = '',
    this.relationDegree = '',
    this.side = '',
    this.notes = '',
    this.fatherId,
    this.motherId,
    this.spouseId,
    this.isSelf = false,
    this.createdAt,
  });

  final String id;
  final String fullName;
  final String photoUrl;
  final String photoPath;
  final String phone;
  final String address;
  final DateTime? birthDate;
  final String gender; // 'male' | 'female' | ''
  final String relationDegree; // erkin matn (masalan: amaki, xola)
  final String side; // 'paternal' | 'maternal' | ''
  final String notes;

  /// Nasab daraxti bog'lanishlari (xuddi shu foydalanuvchi ro'yxatidagi personId).
  final String? fatherId;
  final String? motherId;
  final String? spouseId;

  /// Server tomonidan «Мен» yozuvi (profil bilan sinxron).
  final bool isSelf;

  final DateTime? createdAt;

  /// Keyingi tug'ilgan kun sanasi (bugundan boshlab).
  DateTime? get nextBirthday {
    if (birthDate == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var d = DateTime(now.year, birthDate!.month, birthDate!.day);
    if (d.isBefore(today)) {
      d = DateTime(now.year + 1, birthDate!.month, birthDate!.day);
    }
    return d;
  }

  int? get daysUntilBirthday {
    final nb = nextBirthday;
    if (nb == null) return null;
    final now = DateTime.now();
    return nb.difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  int? get age {
    if (birthDate == null) return null;
    final now = DateTime.now();
    var a = now.year - birthDate!.year;
    if (now.month < birthDate!.month ||
        (now.month == birthDate!.month && now.day < birthDate!.day)) {
      a--;
    }
    return a;
  }

  factory RelativePerson.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return RelativePerson(
      id: doc.id,
      fullName: (d['fullName'] ?? '') as String,
      photoUrl: (d['photoUrl'] ?? '') as String,
      photoPath: (d['photoPath'] ?? '') as String,
      phone: (d['phone'] ?? '') as String,
      address: (d['address'] ?? '') as String,
      birthDate: (d['birthDate'] as Timestamp?)?.toDate(),
      gender: (d['gender'] ?? '') as String,
      relationDegree: (d['relationDegree'] ?? '') as String,
      side: (d['side'] ?? '') as String,
      notes: (d['notes'] ?? '') as String,
      fatherId: d['fatherId'] as String?,
      motherId: d['motherId'] as String?,
      spouseId: d['spouseId'] as String?,
      isSelf: d['isSelf'] == true,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'fullName': fullName,
        'photoUrl': photoUrl,
        'photoPath': photoPath,
        'phone': phone,
        'address': address,
        'birthDate': birthDate == null ? null : Timestamp.fromDate(birthDate!),
        'gender': gender,
        'relationDegree': relationDegree,
        'side': side,
        'notes': notes,
        'fatherId': fatherId,
        'motherId': motherId,
        'spouseId': spouseId,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
