import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/home_ticker_ad.dart';

/// `home_ticker_ads` — bosh ekran begushchaya qator matnlari.
class HomeTickerRepository {
  HomeTickerRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('home_ticker_ads');

  /// Berilgan modul (`home_search`) va rol uchun faol matnlar.
  /// Serverda `module`+`active` filter + priority tartib + limit;
  /// audience/vaqt oralig'i clientda (OR + interval).
  /// Index hali tayyor bo'lmasa — priority-only query'ga fallback.
  Stream<List<HomeTickerAd>> watchForModule(
    String module,
    String role, {
    int limit = 40,
  }) {
    List<HomeTickerAd> parse(
      QuerySnapshot<Map<String, dynamic>> snap, {
      required bool serverFiltered,
    }) {
      final now = DateTime.now();
      return snap.docs
          .map(HomeTickerAd.fromDoc)
          .where((a) =>
              (serverFiltered || a.module == module) &&
              (serverFiltered || a.active) &&
              a.text.isNotEmpty &&
              a.isVisibleForRole(role) &&
              a.isVisibleNow(now))
          .toList(growable: false);
    }

    final primary = _col
        .where('module', isEqualTo: module)
        .where('active', isEqualTo: true)
        .orderBy('priority', descending: true)
        .limit(limit)
        .snapshots();

    return Stream.multi((controller) {
      StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? sub;

      void listenLegacy() {
        sub = _col
            .orderBy('priority', descending: true)
            .limit(limit)
            .snapshots()
            .listen(
          (snap) {
            if (!controller.isClosed) {
              controller.add(parse(snap, serverFiltered: false));
            }
          },
          onError: controller.addError,
          onDone: controller.close,
        );
      }

      sub = primary.listen(
        (snap) {
          if (!controller.isClosed) {
            controller.add(parse(snap, serverFiltered: true));
          }
        },
        onError: (Object e, StackTrace st) {
          debugPrint('HomeTickerRepository.watchForModule primary: $e');
          unawaited(sub?.cancel());
          listenLegacy();
        },
        onDone: controller.close,
      );

      controller.onCancel = () => sub?.cancel();
    });
  }

  /// Admin panel — barcha yozuvlar (faol/faol emas).
  Stream<List<HomeTickerAd>> watchForAdmin({int limit = 100}) {
    return _col
        .orderBy('priority', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs.map(HomeTickerAd.fromDoc).toList(growable: false),
        );
  }

  Future<String> create(HomeTickerAd ad) async {
    final ref = await _col.add(ad.toCreateMap());
    return ref.id;
  }

  Future<void> update(HomeTickerAd ad) async {
    if (ad.id.isEmpty) return;
    await _col.doc(ad.id).update(ad.toUpdateMap());
  }

  Future<void> setActive(String id, bool active) async {
    if (id.isEmpty) return;
    await _col.doc(id).update({
      'active': active,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String id) async {
    if (id.isEmpty) return;
    await _col.doc(id).delete();
  }

  /// Berilgan modulning BARCHA matnlari uchun `durationSec` ni bittada
  /// o'rnatadi. Qaytaradi: yangilangan hujjatlar soni.
  Future<int> setDurationForModule(String module, int durationSec) async {
    final snap = await _col.where('module', isEqualTo: module).get();
    if (snap.docs.isEmpty) return 0;
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {
        'durationSec': durationSec,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return snap.docs.length;
  }

  /// Berilgan modulning BARCHA matnlari uchun `animationStyle` ni bittada
  /// o'rnatadi. Qaytaradi: yangilangan hujjatlar soni.
  Future<int> setAnimationStyleForModule(
      String module, String animationStyle) async {
    final snap = await _col.where('module', isEqualTo: module).get();
    if (snap.docs.isEmpty) return 0;
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {
        'animationStyle': animationStyle,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return snap.docs.length;
  }
}
