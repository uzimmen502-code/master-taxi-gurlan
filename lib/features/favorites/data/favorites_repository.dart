import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/favorite_ref.dart';

/// ❤ Танланганлар маълумот қатлами (`users/{uid}/favorites/{collection_itemId}`).
/// Тестларда сохта амалга ошириш берилади ([FavoritesController]).
abstract class FavoritesRepository {
  /// Ўз танланганлари — илова бўйича БИТТА тингловчи ([FavoritesController]); карточкалар ўқимайди.
  Stream<List<FavoriteRef>> watch(String uid);

  /// Яратиш (rules: update йўқ — мавжуд бўлса ҳам `set` қайта ёзмайди, чақирувчи аввал текширади).
  Future<void> add(String uid, FavoriteRef ref);

  Future<void> remove(String uid, String key);

  /// Манба ҳужжатлари — ФАҚАТ «Танланганлар» экрани очилганда. Қиймат `null` = ҳужжат йўқ ёки ёпиқ;
  /// калит умуман йўқ = аниқлаб бўлмади (тармоқ) — элемент оддий кўрсатилади.
  Future<Map<String, Map<String, dynamic>?>> fetchSources(List<FavoriteRef> refs);
}

class FirestoreFavoritesRepository implements FavoritesRepository {
  FirestoreFavoritesRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Бир фойдаланувчида кўриладиган юқори чегара (cost: битта listener, ≤ шунча ҳужжат).
  static const int watchLimit = 500;

  /// Параллел `get` бўлаги. Рўйхат сўрови (`whereIn` documentId) ишлатилмайди: `ads` ва бошқаларда
  /// list қоидаси get'дан қаттиқроқ — битта ёпиқ ҳужжат бутун бўлакни рад этарди.
  static const int fetchChunk = 10;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('favorites');

  @override
  Stream<List<FavoriteRef>> watch(String uid) => _col(uid)
      .orderBy('addedAt', descending: true)
      .limit(watchLimit)
      .snapshots()
      .map((s) => s.docs.map((d) => FavoriteRef.fromMap(d.id, d.data())).toList());

  @override
  Future<void> add(String uid, FavoriteRef ref) =>
      _col(uid).doc(ref.key).set({...ref.toCreateMap(), 'addedAt': FieldValue.serverTimestamp()});

  @override
  Future<void> remove(String uid, String key) => _col(uid).doc(key).delete();

  @override
  Future<Map<String, Map<String, dynamic>?>> fetchSources(List<FavoriteRef> refs) async {
    final out = <String, Map<String, dynamic>?>{};
    for (var i = 0; i < refs.length; i += fetchChunk) {
      final chunk = refs.sublist(i, i + fetchChunk > refs.length ? refs.length : i + fetchChunk);
      final results = await Future.wait(chunk.map((r) async {
        try {
          final snap = await _db.collection(r.collection).doc(r.itemId).get();
          return (true, snap.exists ? snap.data() : null);
        } on FirebaseException catch (e) {
          // permission-denied — ҳужжат ёпиқ (яширилган/блокланган): «Мавжуд эмас».
          if (e.code == 'permission-denied') return (true, null);
          return (false, null);
        } catch (_) {
          return (false, null);
        }
      }));
      for (var j = 0; j < chunk.length; j++) {
        // Тармоқ/бошқа хато — калит ёзилмайди: экран элементни «мавжуд эмас» деб ЁЛҒОН белгиламайди.
        if (results[j].$1) out[chunk[j].key] = results[j].$2;
      }
    }
    return out;
  }
}
