import 'package:flutter/foundation.dart';

import '../repositories/ev_charging_rules_repository.dart';
import 'ev_charging_rules_config.dart';

/// Ilova ochilganda bir marta yuklanadi — UI sync getterlar uchun.
class EvChargingRulesHolder {
  EvChargingRulesHolder._();

  static EvChargingRulesConfig _current = EvChargingRulesConfig.defaults;

  static EvChargingRulesConfig get current => _current;

  /// EV zaryadlash ekrani ochilganda chaqiring.
  static Future<void> load({bool forceRefresh = false}) async {
    _current =
        await EvChargingRulesRepository().fetchRules(forceRefresh: forceRefresh);
  }

  @visibleForTesting
  static void setForTest(EvChargingRulesConfig config) {
    _current = config;
  }

  @visibleForTesting
  static void resetForTest() {
    _current = EvChargingRulesConfig.defaults;
  }
}
