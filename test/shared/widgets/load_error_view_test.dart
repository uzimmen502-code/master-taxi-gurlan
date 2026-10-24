import 'package:ava_gurlan/shared/widgets/load_error_view.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Yuklash xatosi holati: tushunarli matn (xom `snap.error` emas) + qayta urinish.
/// Lokalizatsiya delegati atayin yo'q — `context.tr` kalitning o'zini qaytaradi.
void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('xom xato matni chiqmaydi — kod bo\'yicha kalit', (t) async {
    await t.pumpWidget(host(LoadErrorView(
      error: FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Missing or insufficient permissions.',
      ),
    )));
    expect(find.text('err_permission'), findsOneWidget);
    expect(find.textContaining('insufficient'), findsNothing);
    expect(find.textContaining('cloud_firestore'), findsNothing);
    // onRetry berilmagan — tugma yo'q.
    expect(find.text('err_retry'), findsNothing);
  });

  testWidgets('noma\'lum xato — err_load_failed; «Qayta urinish» chaqiriladi',
      (t) async {
    var retried = 0;
    await t.pumpWidget(host(LoadErrorView(
      error: Exception('Хатолик: boom'),
      onRetry: () => retried++,
    )));
    expect(find.text('err_load_failed'), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);

    await t.tap(find.text('err_retry'));
    expect(retried, 1);
  });

  testWidgets('messageKey xatodan ustun', (t) async {
    await t.pumpWidget(host(const LoadErrorView(messageKey: 'local_trip_not_found')));
    expect(find.text('local_trip_not_found'), findsOneWidget);
  });

  testWidgets('retry tugmasi kamida 48 dp', (t) async {
    await t.pumpWidget(host(LoadErrorView(
      error: Exception('x'),
      onRetry: () {},
    )));
    final size = t.getSize(find.byType(OutlinedButton));
    expect(size.height, greaterThanOrEqualTo(48));
  });
}
