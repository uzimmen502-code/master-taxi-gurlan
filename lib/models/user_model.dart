import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_address.dart';

/// Firestore'dagi `users/{phoneDigits}` hujjati.
class UserModel {
  final String id;
  final String name;
  final String phone;
  final String gender;
  final String role;
  final String birthDate;

  /// Структурaланган манзил — UI ва курьер учун.
  /// Эски `address` (String) — обратной совместимости учун сақланади.
  final UserAddress address;
  final String addressLegacy;

  final int bonusBalance;

  /// Янгилик/хабарларни охирги марта ўқиган вақт (unread badge учун).
  final DateTime? lastNewsReadAt;

  const UserModel({
    required this.id,
    this.name = '',
    this.phone = '',
    this.gender = 'male',
    this.role = 'user',
    this.birthDate = '',
    this.address = const UserAddress(),
    this.addressLegacy = '',
    this.bonusBalance = 0,
    this.lastNewsReadAt,
  });

  /// Манзил тўлдирилганми? (4 та мажбурий майдон).
  bool get hasCompleteAddress => address.isComplete;

  bool get hasBirthDate => birthDate.trim().isNotEmpty;

  /// UI'да кўрсатиш учун — янги ёки эски.
  String get addressDisplay {
    if (address.isComplete) return address.formatted;
    return addressLegacy;
  }

  factory UserModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return UserModel(
      id: doc.id,
      name: d['name'] ?? '',
      phone: d['phone'] ?? '',
      gender: d['gender'] ?? 'male',
      role: d['role'] ?? 'user',
      birthDate: (d['birthDate'] ?? '') as String,
      address: UserAddress.fromMap(d['address'] as Map<String, dynamic>?),
      addressLegacy: (d['address'] is String)
          ? (d['address'] as String)
          : (d['legacyAddress'] ?? '') as String,
      bonusBalance: (d['bonusBalance'] as num?)?.toInt() ?? 0,
      lastNewsReadAt: (d['lastNewsReadAt'] as Timestamp?)?.toDate(),
    );
  }
}
