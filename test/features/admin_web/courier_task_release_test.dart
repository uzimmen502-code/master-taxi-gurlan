// Admin «Kuryerdan olish» (B1) — qirralar serverdagi CARPET_RELEASE_EDGES /
// AGRO_ADMIN_TRANSITIONS bilan mos, dialog sabab qaytaradi.
//
//   flutter test test/features/admin_web/courier_task_release_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/features/admin_web/utils/courier_task_release.dart';
import 'package:ava_gurlan/features/admin_web/widgets/release_task_dialog.dart';
import 'package:ava_gurlan/models/agro_pickup_order.dart';
import 'package:ava_gurlan/models/carpet_wash_order.dart';

void main() {
  test('gilam: faqat ikki "yo\'lda" holatidan qaytariladi', () {
    expect(carpetReleaseTarget(CarpetWashOrder.statusPickupInDelivery), CarpetWashOrder.statusPickupReady);
    expect(carpetReleaseTarget(CarpetWashOrder.statusReturnInDelivery), CarpetWashOrder.statusReturnReady);
    for (final s in [
      CarpetWashOrder.statusNew,
      CarpetWashOrder.statusAccepted,
      CarpetWashOrder.statusPickupReady,
      CarpetWashOrder.statusPickedUp,
      CarpetWashOrder.statusWashing,
      CarpetWashOrder.statusReturnReady,
      CarpetWashOrder.statusDelivered,
      CarpetWashOrder.statusCancelled,
      '',
      'kelajak',
    ]) {
      expect(carpetReleaseTarget(s), isNull, reason: s);
    }
  });

  test('sut: faqat pickup_in_delivery -> accepted', () {
    expect(agroReleaseTarget(AgroPickupOrder.statusPickupInDelivery), AgroPickupOrder.statusAccepted);
    for (final s in [
      AgroPickupOrder.statusNew,
      AgroPickupOrder.statusAccepted,
      AgroPickupOrder.statusPickedUp,
      AgroPickupOrder.statusCompleted,
      AgroPickupOrder.statusCancelled,
      '',
    ]) {
      expect(agroReleaseTarget(s), isNull, reason: s);
    }
  });

  testWidgets('dialog: sabab ixtiyoriy, "Bekor" -> null', (tester) async {
    String? result = 'untouched';
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showReleaseTaskDialog(context, taskLabel: 'T', resultLabel: 'accepted');
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Kuryerdan olib qo\'yilsinmi?'), findsOneWidget);
    await tester.tap(find.text('Bekor'));
    await tester.pumpAndSettle();
    expect(result, isNull);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  kuryer javob bermadi ');
    await tester.tap(find.widgetWithText(FilledButton, 'Kuryerdan olish'));
    await tester.pumpAndSettle();
    expect(result, 'kuryer javob bermadi');

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Kuryerdan olish'));
    await tester.pumpAndSettle();
    expect(result, '', reason: 'sabab ixtiyoriy: bo\'sh matn qaytadi (null emas)');
  });
}
