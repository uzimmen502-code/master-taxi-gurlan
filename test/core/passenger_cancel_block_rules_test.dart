import 'package:flutter_test/flutter_test.dart';
import 'package:master_taxi_gurlan/core/passenger_cancel_block_rules.dart';
import 'package:master_taxi_gurlan/core/passenger_cancel_rules_holder.dart';

void main() {
  setUpAll(() {
    PassengerCancelRulesHolder.resetForTest();
  });

  final t0 = DateTime(2026, 6, 2, 12, 0, 0);

  group('PassengerCancelBlockRules.effectiveCancelCount', () {
    test('oyna ichida — xom cancelCount qaytariladi', () {
      expect(
        PassengerCancelBlockRules.effectiveCancelCount(
          cancelCount: 3,
          firstCancelAt: t0,
          now: t0.add(const Duration(minutes: 5)),
        ),
        3,
      );
    });

    test('oyna tugagan — CF kabi 0', () {
      expect(
        PassengerCancelBlockRules.effectiveCancelCount(
          cancelCount: 4,
          firstCancelAt: t0,
          now: t0.add(const Duration(minutes: 11)),
        ),
        0,
      );
    });

    test('firstCancelAt null — xom count', () {
      expect(
        PassengerCancelBlockRules.effectiveCancelCount(
          cancelCount: 2,
          firstCancelAt: null,
          now: t0,
        ),
        2,
      );
    });
  });

  group('PassengerBlockState.cancelsUntilBlock', () {
    test('oyna tugagan, Firestore 4 — qolgan 5 (nol deb hisoblanadi)', () {
      const raw = PassengerBlockState(
        cancelCount: 4,
        firstCancelAt: null,
      );
      final state = PassengerBlockState(
        cancelCount: raw.cancelCount,
        firstCancelAt: t0,
      );
      expect(
        PassengerCancelBlockRules.remainingCancelsBeforeBlock(
          state,
          now: t0.add(const Duration(minutes: 11)),
        ),
        5,
      );
    });

    test('oyna ichida 4 bekor — qolgan 1', () {
      final state = PassengerBlockState(
        cancelCount: 4,
        firstCancelAt: t0,
      );
      expect(
        PassengerCancelBlockRules.remainingCancelsBeforeBlock(
          state,
          now: t0.add(const Duration(minutes: 2)),
        ),
        1,
      );
    });
  });
}
