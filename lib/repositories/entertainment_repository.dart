import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/entertainment_video.dart';
import 'intercity_bookings_repository.dart';

/// Йўловчи кинога кириш рад этилди (брон йўқ ёки статус нотўғри).
class EntertainmentAccessException implements Exception {
  const EntertainmentAccessException([
    this.message =
        'Кинони фақат тасдиқланган бронингиз бўлганда томоша қила оласиз.',
  ]);

  final String message;

  @override
  String toString() => message;
}

/// B variant: admin catalog → driver tanlov → yo'lovchi tomoshа.
class EntertainmentRepository {
  EntertainmentRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const maxDriverSelection = 5;

  CollectionReference<Map<String, dynamic>> get _catalog =>
      _db.collection('entertainment_catalog');

  CollectionReference<Map<String, dynamic>> get _drivers =>
      _db.collection('intercity_drivers');

  Stream<List<EntertainmentVideo>> watchCatalog({bool activeOnly = false}) {
    return _catalog.orderBy('sortOrder').snapshots().map((snap) {
      var list = snap.docs.map(EntertainmentVideo.fromDoc).toList();
      if (activeOnly) list = list.where((v) => v.active).toList();
      return list;
    });
  }

  Future<List<EntertainmentVideo>> getCatalog({bool activeOnly = true}) async {
    final snap = await _catalog.orderBy('sortOrder').get();
    var list = snap.docs.map(EntertainmentVideo.fromDoc).toList();
    if (activeOnly) list = list.where((v) => v.active).toList();
    return list;
  }

  Future<String> createCatalogEntry({
    String? id,
    required String title,
    required String storagePath,
    required String downloadUrl,
    int durationSec = 0,
  }) async {
    final ref = id != null ? _catalog.doc(id) : _catalog.doc();
    await ref.set({
      'title': title.trim(),
      'storagePath': storagePath,
      'downloadUrl': downloadUrl,
      'durationSec': durationSec,
      'active': true,
      'sortOrder': DateTime.now().millisecondsSinceEpoch,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> setCatalogActive(String id, bool active) async {
    await _catalog.doc(id).update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> setDriverEntertainmentAllowed(String driverId, bool allowed) async {
    if (driverId.isEmpty) return;
    final ref = _drivers.doc(driverId);
    final data = {
      'entertainmentAllowed': allowed,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final snap = await ref.get();
    if (snap.exists) {
      await ref.update(data);
    } else {
      await ref.set(data);
    }
  }

  Future<void> setDriverEntertainmentIds(
    String driverId,
    List<String> videoIds,
  ) async {
    if (driverId.isEmpty) {
      throw Exception('Ҳайдовчи ID топилмади. Панелни қайта очинг.');
    }
    final ids = videoIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .take(maxDriverSelection)
        .toList();
    final ref = _drivers.doc(driverId);

    // Кэш эмас — сервер ҳолати (админ Kino switch кэшда «ёқилган» кўриниши мумкин).
    final snap = await ref.get(const GetOptions(source: Source.server));
    if (!snap.exists) {
      throw Exception(
        'Рейс профили топилмади. Аввал «Ишга чиқиш» (шахарлараро) қилинг.',
      );
    }
    if (snap.data()?['entertainmentAllowed'] != true) {
      throw Exception(
        'Кино рухсати серверда ёқилмаган. Админ: Shaharlararo → Haydovchilar → '
        'Kino switch (ID: $driverId).',
      );
    }
    try {
      await ref.update({
        'entertainmentIds': ids,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw Exception(
          'Firestore рухсати йўқ (ID: $driverId). '
          'Админ Kino ёқилганини текширинг; rules deploy ва APK янгиланг.',
        );
      }
      throw Exception('Сақлаш хатоси: ${e.message ?? e.code}');
    }
  }

  Future<bool> isEntertainmentAllowed(String driverId) async {
    if (driverId.isEmpty) return false;
    final snap =
        await _drivers.doc(driverId).get(const GetOptions(source: Source.server));
    return snap.data()?['entertainmentAllowed'] == true;
  }

  Future<List<String>> getDriverEntertainmentIds(String driverId) async {
    if (driverId.isEmpty) return const [];
    final snap = await _drivers.doc(driverId).get();
    final raw = snap.data()?['entertainmentIds'];
    if (raw is! List) return const [];
    return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  }

  /// Йўловчи кинoga kirish huquqi (faol bрон).
  Future<bool> userHasEntertainmentAccess({
    required String userPhone,
    required String driverId,
    String? bookingId,
    IntercityBookingsRepository? bookingsRepo,
  }) {
    final repo = bookingsRepo ?? IntercityBookingsRepository();
    return repo.userHasEntertainmentAccess(
      userPhone: userPhone,
      driverId: driverId,
      bookingId: bookingId,
    );
  }

  /// Йўловчи — брон + haydovchi tanlovi tekshiriladi.
  Future<List<EntertainmentVideo>> videosForPassenger({
    required IntercityBookingsRepository bookingsRepo,
    required String userPhone,
    required String driverId,
    String? bookingId,
  }) async {
    final ok = await bookingsRepo.userHasEntertainmentAccess(
      userPhone: userPhone,
      driverId: driverId,
      bookingId: bookingId,
    );
    if (!ok) throw const EntertainmentAccessException();
    return videosForDriver(driverId);
  }

  /// Ҳайдовчи танлаган актив videolar (ichki).
  Future<List<EntertainmentVideo>> videosForDriver(String driverId) async {
    final ids = await getDriverEntertainmentIds(driverId);
    if (ids.isEmpty) return const [];
    final allowed = await isEntertainmentAllowed(driverId);
    if (!allowed) return const [];

    final out = <EntertainmentVideo>[];
    for (final id in ids) {
      final snap = await _catalog.doc(id).get();
      if (!snap.exists) continue;
      final v = EntertainmentVideo.fromDoc(snap);
      if (v.active) out.add(v);
    }
    return out;
  }
}
