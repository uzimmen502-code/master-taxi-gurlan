import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/home/widgets/ava_bottom_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AvaCreateAction?> _open(WidgetTester tester, {required String tapKey}) async {
  AvaCreateAction? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => result = await showAvaCreateSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(tapKey));
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('«＋» менюсида «Ҳайдовчи / Курьер» бор ва driver қайтаради',
      (tester) async {
    final r = await _open(tester, tapKey: 'work_entry_join');
    expect(r, AvaCreateAction.work);
  });

  testWidgets('«＋» менюсида аввалги бешта амал сақланган', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showAvaCreateSheet(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    for (final key in const [
      'home_create_video',
      'home_create_ad',
      'home_create_product',
      'home_create_service',
      'home_create_seller',
      'work_entry_join',
    ]) {
      expect(find.text(key), findsOneWidget, reason: key);
    }
  });
}
