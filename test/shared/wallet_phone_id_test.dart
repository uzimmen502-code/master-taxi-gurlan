import 'package:ava_gurlan/shared/widgets/wallet_topup_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Қурилмада кўрилди: Кабинетдаги «Ҳамён» қаторида баланс чиқмади, чунки
/// Firebase телефони бўш эди. Илованинг ўз телефони (`user_phone`) захира.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('REGRESSION: Firebase тайёр эмас/телефони бўш — сақланган телефондан каноник ID', () async {
    SharedPreferences.setMockInitialValues({'user_phone': '+998 90 123 45 67'});
    expect(await walletPhoneId(), '998901234567');
  });

  test('9 хонали сақланган рақам — 998 билан тўлдирилади', () async {
    SharedPreferences.setMockInitialValues({'user_phone': '901234567'});
    expect(await walletPhoneId(), '998901234567');
  });

  test('телефон умуман йўқ — бўш (ёлғон ID эмас)', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await walletPhoneId(), '');
  });

  test('телефон йўқ — баланс оқими БЎШ (ёлғон «0» эмас)', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await walletBalanceStream().toList(), isEmpty);
  });

  // Қурилмада Кабинет йиқилди: «Bad state: Stream has already been listened to».
  testWidgets('REGRESSION: бир оқимни StreamBuilder КЎП МАРТА қайта яратса ҳам йиқилмайди', (t) async {
    SharedPreferences.setMockInitialValues({});
    final stream = walletBalanceStream();
    Widget host(Key k) => MaterialApp(
          home: StreamBuilder<int>(key: k, stream: stream, builder: (_, s) => Text('${s.hasData}')),
        );
    await t.pumpWidget(host(const ValueKey('a')));
    await t.pumpWidget(host(const ValueKey('b'))); // элемент қайта яратилди
    await t.pumpWidget(host(const ValueKey('c')));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.text('false'), findsOneWidget);
  });

  test('оқимни кетма-кет икки марта тинглаш мумкин', () async {
    SharedPreferences.setMockInitialValues({});
    final s = walletBalanceStream();
    expect(await s.toList(), isEmpty);
    // Манба тугаган бўлса ҳам иккинчи тингловчи хато бермайди.
    await expectLater(s, emitsDone);
  });
}
