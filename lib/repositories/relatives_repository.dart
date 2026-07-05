import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../core/utils/firebase_functions_errors.dart';
import '../models/relative_event.dart';
import '../models/relative_person.dart';
import '../models/relative_photo.dart';

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
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('addRelativePerson')
          .call({
        'fullName': person.fullName,
        'gender': person.gender,
        'photoUrl': person.photoUrl,
        'photoPath': person.photoPath,
        'phone': person.phone,
        'address': person.address,
        'relationDegree': person.relationDegree,
        'side': person.side,
        'notes': person.notes,
        'birthDateMs': person.birthDate?.millisecondsSinceEpoch,
        'fatherId': person.fatherId,
        'motherId': person.motherId,
        'spouseId': person.spouseId,
      });
      final data = Map<String, dynamic>.from(res.data as Map);
      return (data['personId'] ?? '') as String;
    } on FirebaseFunctionsException catch (e) {
      throw FirebaseException(
        plugin: 'cloud_functions',
        code: e.code,
        message: firebaseFunctionsUserMessage(e),
      );
    }
  }

  Future<void> updatePerson(
      String userId, String personId, RelativePerson person) async {
    await _people(userId).doc(personId).set(
          person.toMap(),
          SetOptions(merge: true),
        );
  }

  Future<void> deletePerson(String userId, String personId) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('deleteRelativePerson')
          .call({'personId': personId});
    } on FirebaseFunctionsException catch (e) {
      throw FirebaseException(
        plugin: 'cloud_functions',
        code: e.code,
        message: firebaseFunctionsUserMessage(e),
      );
    }
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

  // ─── Fotoalbom (har bir qarindosh uchun) ──────────────────────────────

  CollectionReference<Map<String, dynamic>> _album(
          String userId, String personId) =>
      _people(userId).doc(personId).collection('photos');

  Stream<List<RelativePhoto>> watchAlbum(String userId, String personId) {
    return _album(userId, personId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(RelativePhoto.fromDoc).toList(growable: false));
  }

  Future<void> addAlbumPhoto(
      String userId, String personId, RelativePhoto photo) async {
    await _album(userId, personId).add({
      ...photo.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteAlbumPhoto(
      String userId, String personId, String photoId) async {
    await _album(userId, personId).doc(photoId).delete();
  }
}
