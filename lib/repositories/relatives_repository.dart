import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/relative_event.dart';
import '../models/relative_person.dart';

/// Foydalanuvchining shaxsiy qarindoshlar ro'yxati — `relatives/{userId}/people`.
class RelativesRepository {
  RelativesRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _people(String userId) =>
      _db.collection('relatives').doc(userId).collection('people');

  Stream<List<RelativePerson>> watchPeople(String userId) {
    return _people(userId)
        .orderBy('fullName')
        .snapshots()
        .map((s) => s.docs.map(RelativePerson.fromDoc).toList(growable: false));
  }

  /// Tug'ilgan kuni bor qarindoshlar — keyingi BD gacha kun bo'yicha tartiblangan.
  List<RelativePerson> upcomingBirthdays(List<RelativePerson> all) {
    final withBd = all.where((p) => p.birthDate != null).toList()
      ..sort((a, b) =>
          (a.daysUntilBirthday ?? 9999).compareTo(b.daysUntilBirthday ?? 9999));
    return withBd;
  }

  Future<String> addPerson(String userId, RelativePerson person) async {
    final ref = await _people(userId).add({
      ...person.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updatePerson(
      String userId, String personId, RelativePerson person) async {
    await _people(userId).doc(personId).set(
          person.toMap(),
          SetOptions(merge: true),
        );
  }

  Future<void> deletePerson(String userId, String personId) async {
    await _people(userId).doc(personId).delete();
  }

  // ─── Sanalar / uchrashuvlar (eslatmalar) ──────────────────────────────

  CollectionReference<Map<String, dynamic>> _events(String userId) =>
      _db.collection('relatives').doc(userId).collection('events');

  Stream<List<RelativeEvent>> watchEvents(String userId) {
    return _events(userId)
        .orderBy('date')
        .snapshots()
        .map((s) => s.docs.map(RelativeEvent.fromDoc).toList(growable: false));
  }

  /// Kelayotgan sanalar — keyingi yuz berishgacha kun bo'yicha tartiblangan.
  /// O'tib ketgan bir martalik sanalar chiqarib tashlanadi.
  List<RelativeEvent> upcomingEvents(List<RelativeEvent> all) {
    final list = all.where((e) => !e.isPast).toList()
      ..sort((a, b) => a.daysUntil.compareTo(b.daysUntil));
    return list;
  }

  Future<String> addEvent(String userId, RelativeEvent event) async {
    final ref = await _events(userId).add({
      ...event.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateEvent(
      String userId, String eventId, RelativeEvent event) async {
    await _events(userId).doc(eventId).set(
          event.toMap(),
          SetOptions(merge: true),
        );
  }

  Future<void> deleteEvent(String userId, String eventId) async {
    await _events(userId).doc(eventId).delete();
  }
}
