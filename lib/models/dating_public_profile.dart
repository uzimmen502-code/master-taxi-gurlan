import 'package:cloud_firestore/cloud_firestore.dart';

/// `dating_profiles_public/{uid}` — танишув профилининг ОЧИҚ кўчирмаси.
///
/// Бош саҳифадаги 9-бўлим АЙНАН шуни ўқийди. Бу ерда фақат исм, жинс ва
/// туғилган йил бор: расм, шаҳар, «ҳақида», иш ва маълумот майдонлари
/// умуман йўқ — Firestore ҳужжатнинг бир қисмини қайтара олмагани учун,
/// бўлим уларни чизмаса ҳам, тўлиқ профилни ўқиш қурилмага ортиқча
/// маълумот юборарди.
///
/// Ёзувни CF `onDatingProfileWriteSyncPublic` юритади ва у фақат
/// тасдиқланган ҳамда фаол профиллар учун мавжуд бўлади.
class DatingPublicProfile {
  const DatingPublicProfile({
    required this.userId,
    required this.displayName,
    required this.gender,
    required this.birthYear,
    this.lastActive,
  });

  final String userId;
  final String displayName;

  /// `male` | `female`.
  final String gender;
  final int birthYear;
  final DateTime? lastActive;

  /// Ёш — туғилган йилдан ҳисобланади (эскирмаслиги учун йил сақланади).
  int? get age {
    if (birthYear < 1900) return null;
    return DateTime.now().year - birthYear;
  }

  factory DatingPublicProfile.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data() ?? const <String, dynamic>{};
    return DatingPublicProfile(
      userId: doc.id,
      displayName: (d['displayName'] as String?)?.trim() ?? '',
      gender: (d['gender'] as String?) ?? '',
      birthYear: (d['birthYear'] as num?)?.toInt() ?? 0,
      lastActive: (d['lastActive'] as Timestamp?)?.toDate(),
    );
  }
}
