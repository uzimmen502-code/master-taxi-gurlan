import 'package:cloud_firestore/cloud_firestore.dart';

/// `drivers/{uid}` hujjatining qisqacha ko'rinishi.
class DriverStats {
  final String id;
  final double rating;
  final int ratingCount;

  const DriverStats({
    required this.id,
    this.rating = 0.0,
    this.ratingCount = 0,
  });

  factory DriverStats.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return DriverStats(
      id: doc.id,
      rating: (d['rating'] as num?)?.toDouble() ?? 0.0,
      ratingCount: (d['ratingCount'] as num?)?.toInt() ?? 0,
    );
  }
}
