/// Yo'lovchi bekor qilish bloki (marshrut) — Firestore `config/passenger_cancel_block`.
/// CF `getPassengerCancelRules` bilan mos (default qiymatlar bir xil bo'lishi kerak).
class PassengerCancelRulesConfig {
  const PassengerCancelRulesConfig({
    required this.cancelLimit,
    required this.windowMinutes,
    required this.blockMinutes,
  });

  final int cancelLimit;
  final int windowMinutes;
  final int blockMinutes;

  static const String firestoreDocPath = 'passenger_cancel_block';
  static const String firestoreCollection = 'config';

  /// Offline / hujjat yo'q — CF `PASSENGER_CANCEL_RULES_DEFAULTS` bilan sinxron.
  static const PassengerCancelRulesConfig defaults = PassengerCancelRulesConfig(
    cancelLimit: 5,
    windowMinutes: 10,
    blockMinutes: 10,
  );

  factory PassengerCancelRulesConfig.fromMap(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return defaults;
    return PassengerCancelRulesConfig(
      cancelLimit: _positiveInt(json['cancelLimit'], defaults.cancelLimit),
      windowMinutes: _positiveInt(json['windowMinutes'], defaults.windowMinutes),
      blockMinutes: _positiveInt(json['blockMinutes'], defaults.blockMinutes),
    );
  }

  static int _positiveInt(Object? v, int fallback) {
    final n = (v is num) ? v.toInt() : int.tryParse('$v');
    if (n == null || n < 1) return fallback;
    return n;
  }
}
