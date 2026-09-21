import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/ev_charging_rules_config.dart';

/// `config/ev_charging` — EV zaryadlash nuqtalari modul sozlamalari.
class EvChargingRulesRepository {
  EvChargingRulesRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const _cacheDuration = Duration(minutes: 5);

  EvChargingRulesConfig? _cached;
  DateTime? _cachedAt;

  DocumentReference<Map<String, dynamic>> get _docRef => _db
      .collection(EvChargingRulesConfig.firestoreCollection)
      .doc(EvChargingRulesConfig.firestoreDocPath);

  /// Firestore dan (5 min kesh) yoki [EvChargingRulesConfig.defaults].
  Future<EvChargingRulesConfig> fetchRules({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cached != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _cacheDuration) {
      return _cached!;
    }

    try {
      final snap = await _docRef.get();
      final rules = snap.exists
          ? EvChargingRulesConfig.fromMap(snap.data())
          : EvChargingRulesConfig.defaults;
      _cached = rules;
      _cachedAt = DateTime.now();
      return rules;
    } catch (e, st) {
      debugPrint('EvChargingRulesRepository.fetchRules: $e\n$st');
      return EvChargingRulesConfig.defaults;
    }
  }
}
