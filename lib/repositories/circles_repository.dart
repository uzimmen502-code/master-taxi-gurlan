import 'package:cloud_firestore/cloud_firestore.dart';

import '../features/circles/utils/school_normalizer.dart';
import '../models/circle.dart';
import '../models/circle_chat_message.dart';
import '../models/circle_event.dart';
import '../models/circle_member.dart';
import '../models/circle_photo.dart';
import '../models/circle_post.dart';

/// "Mening yaqinlarim" — Circle (Davra) dvigateli. MVP: sinfdoshlar.
///
/// Avto-qo'shilish: foydalanuvchi maktab + yil kiritsa, deterministik davra
/// ID hosil bo'ladi (`SchoolNormalizer`); davra bor bo'lsa qo'shiladi, yo'q
/// bo'lsa yaratiladi (birinchi a'zo — owner). Adashsa `leaveCircle`.
///
/// userId — har joyda `canonicalPhoneId` (998...), `users` doc id bilan bir xil.
class CirclesRepository {
  CirclesRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _circles =>
      _db.collection('circles');

  String classCircleId(String school, int year) =>
      SchoolNormalizer.classCircleId(school, year);

  Future<Circle?> getCircle(String circleId) async {
    final snap = await _circles.doc(circleId).get();
    return snap.exists ? Circle.fromDoc(snap) : null;
  }

  /// Avto-qo'shilishdan oldin "mavjud davra taklifi" — deterministik ID bo'yicha.
  Future<Circle?> suggestClassCircle(String school, int year) {
    return getCircle(classCircleId(school, year));
  }

  Stream<Circle?> watchCircle(String circleId) {
    return _circles
        .doc(circleId)
        .snapshots()
        .map((s) => s.exists ? Circle.fromDoc(s) : null);
  }

  /// Sinf davrasiga avto-qo'shilish (yoki yaratish). Atomik tranzaksiya:
  /// davrani yaratadi/topadi + a'zolikni yozadi + memberCount'ni yangilaydi.
  Future<Circle> joinOrCreateClassCircle({
    required String school,
    required int year,
    required CircleMember member,
  }) async {
    final id = classCircleId(school, year);
    final normKey = SchoolNormalizer.normalizeKey(school);
    final circleRef = _circles.doc(id);
    final memberRef = circleRef.collection('members').doc(member.userId);

    await _db.runTransaction((tx) async {
      final cSnap = await tx.get(circleRef);
      final mSnap = await tx.get(memberRef);
      final circleIsNew = !cSnap.exists;

      if (circleIsNew) {
        final circle = Circle(
          id: id,
          type: CircleType.classmates,
          title: '${school.trim()}, $year',
          normKey: normKey,
          meta: {'school': school.trim(), 'year': year},
          ownerId: member.userId,
        );
        final map = circle.toCreateMap();
        map['memberCount'] = 1; // birinchi a'zo
        tx.set(circleRef, map);
      } else if (!mSnap.exists) {
        tx.set(
          circleRef,
          {
            'memberCount': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }

      final role = circleIsNew
          ? 'owner'
          : ((mSnap.data()?['role'] as String?) ?? 'member');
      tx.set(
        memberRef,
        member.toWriteMap(overrideRole: role),
        SetOptions(merge: true),
      );
    });

    final fresh = await circleRef.get();
    return Circle.fromDoc(fresh);
  }

  /// "Adashdim" — davradan chiqish (a'zolikni o'chirish + sanoqni kamaytirish).
  Future<void> leaveCircle({
    required String circleId,
    required String userId,
  }) async {
    final circleRef = _circles.doc(circleId);
    final memberRef = circleRef.collection('members').doc(userId);
    await _db.runTransaction((tx) async {
      final mSnap = await tx.get(memberRef);
      if (!mSnap.exists) return;
      tx.delete(memberRef);
      tx.set(
        circleRef,
        {
          'memberCount': FieldValue.increment(-1),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  /// Foydalanuvchi a'zo bo'lgan davralarning ID'lari (collectionGroup).
  Stream<List<String>> watchMyCircleIds(String userId) {
    return _db
        .collectionGroup('members')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((s) => s.docs
            .map((d) => d.reference.parent.parent?.id)
            .whereType<String>()
            .toList(growable: false));
  }

  Stream<List<CircleMember>> watchMembers(String circleId) {
    return _circles
        .doc(circleId)
        .collection('members')
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((s) => s.docs.map(CircleMember.fromDoc).toList(growable: false));
  }

  Stream<List<CirclePost>> watchPosts(String circleId) {
    return _circles
        .doc(circleId)
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(CirclePost.fromDoc).toList(growable: false));
  }

  Future<void> createPost({
    required String circleId,
    required CirclePost post,
  }) async {
    await _circles
        .doc(circleId)
        .collection('posts')
        .add(post.toCreateMap());
  }

  Future<void> deletePost({
    required String circleId,
    required String postId,
  }) async {
    await _circles.doc(circleId).collection('posts').doc(postId).delete();
  }

  // ── Uchrashuvlar ──
  Stream<List<CircleEvent>> watchEvents(String circleId) {
    return _circles
        .doc(circleId)
        .collection('events')
        .orderBy('dateTime', descending: false)
        .snapshots()
        .map((s) => s.docs.map(CircleEvent.fromDoc).toList(growable: false));
  }

  Future<void> createEvent({
    required String circleId,
    required CircleEvent event,
  }) async {
    await _circles.doc(circleId).collection('events').add(event.toCreateMap());
  }

  /// RSVP — faqat o'z javobini o'zgartiradi (attendees.{userId}).
  Future<void> setRsvp({
    required String circleId,
    required String eventId,
    required String userId,
    required String status, // 'yes' | 'no' | 'maybe'
  }) async {
    await _circles
        .doc(circleId)
        .collection('events')
        .doc(eventId)
        .update({'attendees.$userId': status});
  }

  Future<void> deleteEvent({
    required String circleId,
    required String eventId,
  }) async {
    await _circles.doc(circleId).collection('events').doc(eventId).delete();
  }

  // ── Fotoalbom ──
  Stream<List<CirclePhoto>> watchPhotos(String circleId) {
    return _circles
        .doc(circleId)
        .collection('album')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(CirclePhoto.fromDoc).toList(growable: false));
  }

  Future<void> addPhoto({
    required String circleId,
    required CirclePhoto photo,
  }) async {
    await _circles.doc(circleId).collection('album').add(photo.toCreateMap());
  }

  Future<void> deletePhoto({
    required String circleId,
    required String photoId,
  }) async {
    await _circles.doc(circleId).collection('album').doc(photoId).delete();
  }

  // ── Guruh chat ──
  Stream<List<CircleChatMessage>> watchChat(String circleId) {
    return _circles
        .doc(circleId)
        .collection('chat')
        .orderBy('createdAt')
        .limitToLast(200)
        .snapshots()
        .map((s) =>
            s.docs.map(CircleChatMessage.fromDoc).toList(growable: false));
  }

  Future<void> sendChat({
    required String circleId,
    required String senderId,
    required String senderName,
    required String text,
  }) async {
    await _circles.doc(circleId).collection('chat').add(
          CircleChatMessage(
            id: '',
            senderId: senderId,
            senderName: senderName,
            text: text,
          ).toCreateMap(),
        );
  }

  /// Shikoyat — admin web panelda ko'riladi/hal qilinadi (`reports`).
  Future<void> report({
    required String circleId,
    required String targetType, // 'member' | 'post' | 'circle'
    required String targetId,
    required String reporterId,
    String reason = '',
  }) async {
    await _db.collection('reports').add({
      'module': 'circles',
      'circleId': circleId,
      'targetType': targetType,
      'targetId': targetId,
      'reporterId': reporterId,
      'reason': reason,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
