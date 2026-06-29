import 'package:cloud_firestore/cloud_firestore.dart';

/// `circles/{circleId}/events/{eventId}` — uchrashuv. RSVP: attendees[userId] =
/// 'yes' | 'no' | 'maybe'.
class CircleEvent {
  const CircleEvent({
    required this.id,
    required this.title,
    required this.createdBy,
    required this.createdByName,
    this.place = '',
    this.dateTime,
    this.attendees = const {},
    this.createdAt,
  });

  final String id;
  final String title;
  final String createdBy;
  final String createdByName;
  final String place;
  final DateTime? dateTime;
  final Map<String, String> attendees;
  final DateTime? createdAt;

  String? rsvpOf(String userId) => attendees[userId];
  int get yesCount => attendees.values.where((v) => v == 'yes').length;

  factory CircleEvent.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    final raw = (d['attendees'] as Map?) ?? const {};
    return CircleEvent(
      id: doc.id,
      title: (d['title'] ?? '') as String,
      createdBy: (d['createdBy'] ?? '') as String,
      createdByName: (d['createdByName'] ?? '') as String,
      place: (d['place'] ?? '') as String,
      dateTime: (d['dateTime'] as Timestamp?)?.toDate(),
      attendees:
          raw.map((k, v) => MapEntry(k.toString(), v.toString())),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toCreateMap() => {
        'title': title,
        'createdBy': createdBy,
        'createdByName': createdByName,
        'place': place,
        'dateTime': dateTime == null ? null : Timestamp.fromDate(dateTime!),
        'attendees': attendees,
        'createdAt': FieldValue.serverTimestamp(),
      };
}
