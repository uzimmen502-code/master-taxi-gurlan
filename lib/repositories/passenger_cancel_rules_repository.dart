import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/passenger_cancel_rules_config.dart';

/// `config/passenger_cancel_block` — marshrut va local taxi blok qoidalari.
class PassengerCancelRulesRepository {
  PassengerCancelRulesRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static const _cacheDuration = Duration(minutes: 5);

  PassengerCancelRulesConfig? _cached;
  DateTime? _cachedAt;

  DocumentReference<Map<String, dynamic>> get _docRef => _db
      .collection(PassengerCancelRulesConfig.firestoreCollection)
      .doc(PassengerCancelRulesConfig.firestoreDocPath);

  /// Firestore dan (5 min kesh) yoki [PassengerCancelRulesConfig.defaults].
  Future<PassengerCancelRulesConfig> fetchRules({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cached != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _cacheDuration) {
      return _cached!;
    }

    try {
      final snap = await _docRef.get();
      final rules = snap.exists
          ? PassengerCancelRulesConfig.fromMap(snap.data())
          : PassengerCancelRulesConfig.defaults;
      _cached = rules;
      _cachedAt = DateTime.now();
      return rules;
    } catch (e, st) {
      debugPrint('PassengerCancelRulesRepository.fetchRules: $e\n$st');
      return PassengerCancelRulesConfig.defaults;
    }
  }
}
