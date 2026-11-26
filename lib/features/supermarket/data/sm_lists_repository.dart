import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/order_model.dart';
import '../domain/sm_list.dart';

/// «Ҳафталик сават» манбаи. Тестда сохта (тармоқсиз) алмаштирилади.
abstract class SmListsStore {
  Future<List<SmList>> load();

  /// Янги рўйхат (`list.id` бўш — авто id, акс ҳолда шу id); қайтади — ҳужжат id.
  Future<String> create(SmList list);
  Future<void> update(SmList list);
  Future<void> delete(String listId);
}

/// `users/{uid}/sm_lists/{listId}` — шартнома (rules: фақат эгаси ёзади/ўқийди). `uid` — Firebase Auth.
class FirestoreSmListsStore implements SmListsStore {
  FirestoreSmListsStore({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> _col() {
    final uid = _auth.currentUser?.uid ?? '';
    if (uid.isEmpty) throw StateError('SM_LISTS_NO_AUTH');
    return _db.collection('users').doc(uid).collection('sm_lists');
  }

  /// Битта сўров, ≤ [kSmMaxLists] + 1 ҳужжат (37-банд).
  @override
  Future<List<SmList>> load() async {
    final snap = await _col().limit(kSmMaxLists + 1).get();
    final out = [
      for (final d in snap.docs)
        SmList.fromMap(d.id, d.data(), updatedAt: (d.data()['updatedAt'] as Timestamp?)?.toDate()),
    ];
    out.sort((a, b) => (b.updatedAt ?? DateTime(0)).compareTo(a.updatedAt ?? DateTime(0)));
    return out;
  }

  /// `list.id` бўш — янги авто id; акс ҳолда шу id (саватча — `weekly_basket`, эга 2026-11-28).
  @override
  Future<String> create(SmList list) async {
    final ref = list.id.isEmpty ? _col().doc() : _col().doc(list.id);
    await ref.set({
      ...list.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  @override
  Future<void> update(SmList list) =>
      _col().doc(list.id).update({...list.toMap(), 'updatedAt': FieldValue.serverTimestamp()});

  @override
  Future<void> delete(String listId) => _col().doc(listId).delete();
}

/// Рўйхат сақланган пайтдаги нархлар (`offerId → сўм`) — ФАҚАТ шу қурилмада, «нарх ўзгарди» кўрсатиш учун.
/// Сервер ҳужжатига ёзилмайди (шартномада нарх майдони йўқ). Йўқолса — нарх ўзгариши шунчаки кўрсатилмайди.
class SmListPriceMemo {
  static const _prefix = 'sm_list_prices_v1_';

  Future<Map<String, int>> load(String listId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$listId');
      if (raw == null) return const {};
      final m = jsonDecode(raw);
      if (m is! Map) return const {};
      return {
        for (final e in m.entries)
          if (e.key is String && e.value is int) e.key as String: e.value as int,
      };
    } catch (e) {
      debugPrint('[SmListPriceMemo] load: $e');
      return const {};
    }
  }

  Future<void> save(String listId, Map<String, int> prices) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefix$listId', jsonEncode(prices));
    } catch (e) {
      debugPrint('[SmListPriceMemo] save: $e');
    }
  }

  Future<void> remove(String listId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$listId');
    } catch (e) {
      debugPrint('[SmListPriceMemo] remove: $e');
    }
  }
}

/// Супермаркет буюртмалари тарихи манбаи (тестда сохта).
typedef SmOrdersLoader = Future<List<OrderModel>> Function();

/// `orders`: `userPhone` (телефон аликслари, мавжуд `OrdersRepository.watchByUser` қоидаси) + `subtype ==
/// 'supermarket'`, ≤ 50; тартиб клиентда (композит индекс шарт эмас — фақат тенглик/in фильтрлари).
Future<List<OrderModel>> loadSupermarketOrders({FirebaseFirestore? db, int limit = 50}) async {
  final prefs = await SharedPreferences.getInstance();
  final aliases = phoneAliases(phoneDigits(prefs.getString('user_phone') ?? ''));
  if (aliases.isEmpty) return const [];
  final snap = await (db ?? FirebaseFirestore.instance)
      .collection('orders')
      .where('userPhone', whereIn: aliases)
      .where('subtype', isEqualTo: 'supermarket')
      .limit(limit)
      .get();
  final list = [for (final d in snap.docs) OrderModel.fromDoc(d)]..retainWhere((o) => o.isSupermarket);
  list.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
  return list;
}
