import 'package:cloud_firestore/cloud_firestore.dart';

/// Davra turi. MVP — faqat `classmates`. Keyin: relatives/coursemates/colleagues.
enum CircleType { classmates, coursemates, colleagues, relatives }

CircleType circleTypeFromString(String? s) {
  switch (s) {
    case 'coursemates':
      return CircleType.coursemates;
    case 'colleagues':
      return CircleType.colleagues;
    case 'relatives':
      return CircleType.relatives;
    case 'classmates':
    default:
      return CircleType.classmates;
  }
}

String circleTypeToString(CircleType t) => t.name;

/// `circles/{circleId}` — umumiy "Davra" hujjati.
///
/// Sinfdosh (MVP): davra = maktab + bitirgan yil. Sinf harfi keyin kichik-guruh
/// (`subgroups`) sifatida qo'shiladi (odam ko'paysa). `meta` — typega bog'liq
/// maydonlar.
class Circle {
  const Circle({
    required this.id,
    required this.type,
    required this.title,
    required this.normKey,
    required this.meta,
    this.ownerId = '',
    this.memberCount = 0,
    this.subgroupsEnabled = false,
  });

  final String id;
  final CircleType type;
  final String title;

  /// Avto-qo'shilish kaliti (maktab nomidan normallashtirilgan).
  final String normKey;

  /// Typega bog'liq metadata. classmates: { school, year, classLabel? }.
  final Map<String, dynamic> meta;

  final String ownerId;
  final int memberCount;
  final bool subgroupsEnabled;

  String get school => (meta['school'] ?? '') as String;
  int get year => (meta['year'] as num?)?.toInt() ?? 0;

  factory Circle.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return Circle(
      id: doc.id,
      type: circleTypeFromString(d['type'] as String?),
      title: (d['title'] ?? '') as String,
      normKey: (d['normKey'] ?? '') as String,
      meta: Map<String, dynamic>.from(
          (d['meta'] as Map?) ?? const <String, dynamic>{}),
      ownerId: (d['ownerId'] ?? '') as String,
      memberCount: (d['memberCount'] as num?)?.toInt() ?? 0,
      subgroupsEnabled: d['subgroupsEnabled'] == true,
    );
  }

  /// Yangi davra yaratishda yoziladigan maydonlar (server timestamp bilan).
  Map<String, dynamic> toCreateMap() => {
        'type': circleTypeToString(type),
        'title': title,
        'normKey': normKey,
        'meta': meta,
        'ownerId': ownerId,
        'memberCount': 0,
        'subgroupsEnabled': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
