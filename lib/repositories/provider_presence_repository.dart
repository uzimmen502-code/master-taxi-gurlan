// `provider_presence` — таклифчининг жонли ҳолати (13.6.3).
//
// Бу коллекция учун ҚОИДА ва ИНДЕКС анчадан бери бор эди, лекин на
// ёзувчи, на ўқувчи ёзилган эди (продакшнда 0 ҳужжат). Ўқувчи томон —
// `functions_demand/sources/presence_geo.js`, тозалаш —
// `functions_demand/api/maintenance.js` → `makePresenceSweeper`.
// Бу файл ЁЗУВЧИ томон.
//
// ── ID ҚОИДАСИ ─────────────────────────────────────────────────────────
// Ҳужжат калити — КАНОН 12 хонали телефон (`canonicalUserId`). Эски
// `couriers` коллекциясида 9 ва 12 хонали шакллар ёнма-ён яшайди, лекин
// ядро базага фақат канон шаклни ёзади (`functions_demand/core/ids.js`).
// Сервер таклифчи кимлигини АЙНАН КАЛИТдан олади, ҳужжат ичидаги
// майдондан эмас — шунинг учун нотўғри калит жимгина «топилмайди»га
// айланади.
//
// Канон шаклга келмайдиган телефон учун ёзув УМУМАН қилинмайди: бундай
// ҳужжат matching'да `matchKey()` хатосига олиб келарди.

import 'package:cloud_firestore/cloud_firestore.dart';

import '../features/demand_offer/domain/canonical_id.dart';
import '../models/provider_presence.dart';

class ProviderPresenceRepository {
  ProviderPresenceRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const String collectionName = 'provider_presence';

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(collectionName);

  /// GPS heartbeat.
  ///
  /// `merge: true` — ҳужжатда sweep ёзган `offlineAt`/`offlineReason`
  /// қолиши мумкин ва улар ўчирилмайди (қоида фақат клиент уларга
  /// ТЕГИШИНИ тақиқлайди, туришини эмас).
  ///
  /// `isOnline: true` ҳар heartbeat'да келади — модел изоҳидаги 3-банд.
  Future<void> upsert(ProviderPresence p) async {
    final id = canonicalUserId(p.providerId);
    if (id.isEmpty) return;
    await _col.doc(id).set({
      ...p.toUpsertMap(),
      // Калит билан АЙНАН бир хил бўлиши шарт (қоида текширади).
      'providerId': id,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Фойдаланувчи «Онлайн» тугмасини ўчирди ёки тизимдан чиқди.
  ///
  /// `update` ишлатилади, `set` эмас: ҳужжат бўлмаса — ўчириш учун ҳам
  /// ҳеч нарса йўқ. Бундай ҳолда Firestore `not-found` эмас,
  /// `permission-denied` қайтаради (қоида `resource.data`га таянади) —
  /// иккиси ҳам чақирувчи учун бир хил: эътиборсиз.
  Future<void> goOffline(String providerId) async {
    final id = canonicalUserId(providerId);
    if (id.isEmpty) return;
    await _col.doc(id).update({
      'isOnline': false,
      'providerId': id,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
