import 'package:cloud_firestore/cloud_firestore.dart';

/// Dating profil fotosi.
class DatingPhoto {
  const DatingPhoto({required this.url, this.path = ''});
  final String url;
  final String path;

  factory DatingPhoto.fromMap(Map<String, dynamic> m) =>
      DatingPhoto(url: (m['url'] ?? '') as String, path: (m['path'] ?? '') as String);

  Map<String, dynamic> toMap() => {'url': url, 'path': path};
}

/// `dating_profiles/{uid}` — tanishuv profili (admin moderatsiyasidan o'tadi).
class DatingProfile {
  const DatingProfile({
    required this.userId,
    required this.displayName,
    required this.gender,
    required this.birthYear,
    this.city = '',
    this.about = '',
    this.maritalStatus = '',
    this.education = '',
    this.job = '',
    this.photos = const [],
    this.status = 'pending',
    this.rejectionReason = '',
    this.active = true,
    this.lastActive,
    this.prefMinAge = 18,
    this.prefMaxAge = 80,
  });

  final String userId;
  final String displayName;
  final String gender; // 'male' | 'female'
  final int birthYear;
  final String city;
  final String about;
  final String maritalStatus; // 'single'|'divorced'|'widowed'|''
  final String education;
  final String job;
  final List<DatingPhoto> photos;
  final String status; // 'pending'|'approved'|'rejected'|'blocked'
  final String rejectionReason;
  final bool active;
  final DateTime? lastActive;

  /// Tavsiyada кўрсатилadigan ёш oralig‘i (фойдаланувчи танлайди).
  final int prefMinAge;
  final int prefMaxAge;

  int? get age {
    if (birthYear < 1900) return null;
    return DateTime.now().year - birthYear;
  }

  bool get isApproved => status == 'approved';
  String get firstPhoto => photos.isNotEmpty ? photos.first.url : '';

  factory DatingProfile.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    final rawPhotos = (d['photos'] as List?) ?? const [];
    return DatingProfile(
      userId: doc.id,
      displayName: (d['displayName'] ?? '') as String,
      gender: (d['gender'] ?? '') as String,
      birthYear: (d['birthYear'] ?? 0) as int,
      city: (d['city'] ?? '') as String,
      about: (d['about'] ?? '') as String,
      maritalStatus: (d['maritalStatus'] ?? '') as String,
      education: (d['education'] ?? '') as String,
      job: (d['job'] ?? '') as String,
      photos: rawPhotos
          .whereType<Map>()
          .map((m) => DatingPhoto.fromMap(Map<String, dynamic>.from(m)))
          .toList(growable: false),
      status: (d['status'] ?? 'pending') as String,
      rejectionReason: (d['rejectionReason'] ?? '') as String,
      active: (d['active'] ?? true) as bool,
      lastActive: (d['lastActive'] as Timestamp?)?.toDate(),
      prefMinAge: _readPrefAge(d['prefMinAge'], 18),
      prefMaxAge: _readPrefAge(d['prefMaxAge'], 80),
    );
  }

  static int _readPrefAge(Object? raw, int fallback) {
    final n = raw is int ? raw : int.tryParse('$raw') ?? fallback;
    return n.clamp(18, 80);
  }

  String get statusLabel {
    switch (status) {
      case 'approved':
        return 'Тасдиқланган';
      case 'rejected':
        return 'Рад этилган';
      case 'blocked':
        return 'Блокланган';
      default:
        return 'Текширувда';
    }
  }
}
