import 'package:flutter/foundation.dart';

import '../repositories/passenger_cancel_rules_repository.dart';
import 'passenger_cancel_rules_config.dart';

/// Ilova ochilganda bir marta yuklanadi — UI sync getterlar uchun.
class PassengerCancelRulesHolder {
  PassengerCancelRulesHolder._();

  static PassengerCancelRulesConfig _current =
      PassengerCancelRulesConfig.defaults;

  static PassengerCancelRulesConfig get current => _current;

  /// `main.dart` / `main_admin.dart` dan Firebase init dan keyin chaqiring.
  static Future<void> load({bool forceRefresh = false}) async {
    _current =
        await PassengerCancelRulesRepository().fetchRules(forceRefresh: forceRefresh);
  }

  @visibleForTesting
  static void setForTest(PassengerCancelRulesConfig config) {
    _current = config;
  }

  @visibleForTesting
  static void resetForTest() {
    _current = PassengerCancelRulesConfig.defaults;
  }
}
