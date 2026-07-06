import 'package:cloud_firestore/cloud_firestore.dart';

/// `intercity_drivers/{driverId}/clients/{userPhone}` aggregation hujjati.
///
/// "Доимий мижоз" базасининг қурилиш бирлиги: ҳар бир (ҳайдовчи, мижоз) жуфти
/// учун счёт юритилади — booking сони, жами тўлов, биринчи/охирги сана.
/// Booking яратилганда атомар тариqда incrementlanadi, bekor qilinsa
/// decrementlanadi (см. `IntercityBookingsRepository`).
class DriverClientStats {
  const DriverClientStats({
    required this.userPhone,
    required this.userName,
    required this.bookingCount,
    required this.completedCount,
    required this.totalSpent,
    required this.firstBookingAt,
    required this.lastBookingAt,
  });

  final String userPhone;
  final String userName;

  /// Жами bron сони (`cancelled`/`expired` қо'шилмайди).
  final int bookingCount;

  /// Шу bronлардан нечтаси `completed` ҳолатига ўтган.
  final int completedCount;

  /// Жами тўланган сум.
  final int totalSpent;

  final DateTime? firstBookingAt;
  final DateTime? lastBookingAt;

  static const empty = DriverClientStats(
    userPhone: '',
    userName: '',
    bookingCount: 0,
    completedCount: 0,
    totalSpent: 0,
    firstBookingAt: null,
    lastBookingAt: null,
  );

  factory DriverClientStats.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    DateTime? tsOpt(String k) {
      final v = d[k];
      if (v is Timestamp) return v.toDate();
      return null;
    }

    return DriverClientStats(
      userPhone: doc.id,
      userName: (d['userName'] ?? '') as String,
      bookingCount: (d['bookingCount'] as num?)?.toInt() ?? 0,
      completedCount: (d['completedCount'] as num?)?.toInt() ?? 0,
      totalSpent: (d['totalSpent'] as num?)?.toInt() ?? 0,
      firstBookingAt: tsOpt('firstBookingAt'),
      lastBookingAt: tsOpt('lastBookingAt'),
    );
  }
}
