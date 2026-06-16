import 'passenger_cancel_rules_config.dart';
import 'passenger_cancel_rules_holder.dart';

/// Yo'lovchi bekor qilish bloki — marshrut uchun.
/// Qiymatlar: Firestore `config/passenger_cancel_block` (yuklash: [PassengerCancelRulesHolder.load]).
/// CF: `getPassengerCancelRules()` — defaultlar bir xil bo'lishi kerak.
class PassengerCancelBlockRules {
  PassengerCancelBlockRules._();

  static int get cancelLimit => PassengerCancelRulesHolder.current.cancelLimit;
  static int get windowMinutes =>
      PassengerCancelRulesHolder.current.windowMinutes;
  static int get blockMinutes => PassengerCancelRulesHolder.current.blockMinutes;

  static Duration get windowDuration => Duration(minutes: windowMinutes);

  /// Kod defaultlari — test va Firestore fallback.
  static const PassengerCancelRulesConfig defaults =
      PassengerCancelRulesConfig.defaults;

  /// CF yangi bekor qilishdan OLDIN qo'llaydigan `cancelCount` (oyna hisobga olinadi).
  static int effectiveCancelCount({
    required int cancelCount,
    DateTime? firstCancelAt,
    DateTime? now,
  }) {
    final t = now ?? DateTime.now();
    if (firstCancelAt == null) return cancelCount;
    if (t.difference(firstCancelAt) > windowDuration) return 0;
    return cancelCount;
  }

  /// Keyingi bekor qilishlardan nechta qolganida blok (CF bilan mos).
  static int remainingCancelsBeforeBlock(
    PassengerBlockState raw, {
    DateTime? now,
  }) {
    if (raw.isBlocked) return 0;
    final effective = effectiveCancelCount(
      cancelCount: raw.cancelCount,
      firstCancelAt: raw.firstCancelAt,
      now: now,
    );
    return (cancelLimit - effective).clamp(0, cancelLimit);
  }
}

/// `users/{phone}/{service}_block/state` hujjati holati.
class PassengerBlockState {
  const PassengerBlockState({
    this.cancelCount = 0,
    this.blockedUntil,
    this.firstCancelAt,
  });

  final int cancelCount;
  final DateTime? blockedUntil;
  final DateTime? firstCancelAt;

  bool get isBlocked {
    final until = blockedUntil;
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  int get effectiveCancelCount => PassengerCancelBlockRules.effectiveCancelCount(
        cancelCount: cancelCount,
        firstCancelAt: firstCancelAt,
      );

  int get cancelsUntilBlock =>
      PassengerCancelBlockRules.remainingCancelsBeforeBlock(this);

  int? get blockMinutesRemaining {
    final until = blockedUntil;
    if (until == null || !isBlocked) return null;
    return until.difference(DateTime.now()).inMinutes + 1;
  }
}
