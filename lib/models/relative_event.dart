import 'package:cloud_firestore/cloud_firestore.dart';

/// Qarindosh bilan bog'liq maxsus sana / uchrashuv turi.
enum RelativeEventType { meeting, anniversary, memorial, other }

extension RelativeEventTypeX on RelativeEventType {
  String get id {
    switch (this) {
      case RelativeEventType.meeting:
        return 'meeting';
      case RelativeEventType.anniversary:
        return 'anniversary';
      case RelativeEventType.memorial:
        return 'memorial';
      case RelativeEventType.other:
        return 'other';
    }
  }

  String get emoji {
    switch (this) {
      case RelativeEventType.meeting:
        return '📅';
      case RelativeEventType.anniversary:
        return '💍';
      case RelativeEventType.memorial:
        return '🕯';
      case RelativeEventType.other:
        return '⭐';
    }
  }

  String get label {
    switch (this) {
      case RelativeEventType.meeting:
        return 'Учрашув';
      case RelativeEventType.anniversary:
        return 'Йил саналари (никоҳ ва ҳ.к.)';
      case RelativeEventType.memorial:
        return 'Хотира (йил оши ва ҳ.к.)';
      case RelativeEventType.other:
        return 'Бошқа';
    }
  }

  static RelativeEventType fromId(String? raw) {
    switch (raw) {
      case 'meeting':
        return RelativeEventType.meeting;
      case 'anniversary':
        return RelativeEventType.anniversary;
      case 'memorial':
        return RelativeEventType.memorial;
      default:
        return RelativeEventType.other;
    }
  }
}

/// `relatives/{userId}/events` — shaxsiy sana/uchrashuv eslatmasi.
class RelativeEvent {
  const RelativeEvent({
    required this.id,
    required this.title,
    required this.date,
    this.repeatYearly = false,
    this.personIds = const [],
    this.place = '',
    this.note = '',
    this.type = RelativeEventType.other,
    this.createdAt,
  });

  final String id;
  final String title;
  final DateTime date;

  /// Har yili takrorlanadigan sana (tug'ilgan kun emas — masalan nikoh yili).
  final bool repeatYearly;

  /// Bog'langan qarindoshlar (personId).
  final List<String> personIds;
  final String place;
  final String note;
  final RelativeEventType type;
  final DateTime? createdAt;

  factory RelativeEvent.fromDoc(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return RelativeEvent(
      id: doc.id,
      title: (d['title'] ?? '') as String,
      date: (d['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      repeatYearly: (d['repeatYearly'] ?? false) as bool,
      personIds: ((d['personIds'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      place: (d['place'] ?? '') as String,
      note: (d['note'] ?? '') as String,
      type: RelativeEventTypeX.fromId(d['type'] as String?),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'date': Timestamp.fromDate(date),
        'repeatYearly': repeatYearly,
        'personIds': personIds,
        'place': place,
        'note': note,
        'type': type.id,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Keyingi yuz beradigan sana (yillik takror bo'lsa — joriy/keyingi yil).
  DateTime get nextOccurrence {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (!repeatYearly) {
      return DateTime(date.year, date.month, date.day);
    }
    var candidate = DateTime(now.year, date.month, date.day);
    if (candidate.isBefore(today)) {
      candidate = DateTime(now.year + 1, date.month, date.day);
    }
    return candidate;
  }

  /// Bugundan keyingi yuz berishgacha kun (o'tib ketgan bir martalik = manfiy).
  int get daysUntil {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return nextOccurrence.difference(today).inDays;
  }

  /// Yillik takrorlanmaydigan va allaqachon o'tib ketgan sana.
  bool get isPast => !repeatYearly && daysUntil < 0;
}
