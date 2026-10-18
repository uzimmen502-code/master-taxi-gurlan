import 'dart:async';

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

  // Қурилмада: манба қиймат берди (лог кўрсатди), лекин қатор «номаълум»да қолди.
  group('restartableBroadcast + StreamBuilder', () {
    Widget host(Stream<int> s) => MaterialApp(
          home: StreamBuilder<int>(stream: s, builder: (_, snap) => Text(snap.hasData ? 'v${snap.data}' : 'none')),
        );

    testWidgets('асинхрон келган қиймат StreamBuilder\'да кўринади', (t) async {
      final s = restartableBroadcast<int>(() async* {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        yield 19562;
      });
      await t.pumpWidget(host(s));
      expect(find.text('none'), findsOneWidget);
      await t.pump(const Duration(milliseconds: 50));
      expect(find.text('v19562'), findsOneWidget);
    });

    testWidgets('қиймат тингловчи қўшилган заҳоти ЎЗИ келса ҳам йўқолмайди', (t) async {
      final s = restartableBroadcast<int>(() => Stream<int>.value(7));
      await t.pumpWidget(host(s));
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      expect(find.text('v7'), findsOneWidget);
    });

    // Қурилмада ушланган нуқсон: қиймат келди, кейин қатор қайта қурилиб ЯНГИ
    // StreamBuilder кеч уланди — қиймат такрорланмагани учун «кутилмоқда»да қолди.
    testWidgets('REGRESSION: қиймат келгач ЯНГИ StreamBuilder уланса ҳам охирги қийматни олади', (t) async {
      final c = StreamController<int>();
      final s = restartableBroadcast<int>(() => c.stream);
      Widget hostK(Key k) => MaterialApp(
            home: StreamBuilder<int>(key: k, stream: s, builder: (_, snap) => Text(snap.hasData ? 'v${snap.data}' : 'none')),
          );
      await t.pumpWidget(hostK(const ValueKey('a')));
      c.add(19562);
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      expect(find.text('v19562'), findsOneWidget);
      // Элемент қайта яратилди (янги StreamBuilder, янги тингловчи).
      await t.pumpWidget(hostK(const ValueKey('b')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      expect(find.text('v19562'), findsOneWidget, reason: 'янги тингловчи охирги қийматни олиши керак');
      c.add(20000);
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      expect(find.text('v20000'), findsOneWidget);
      await c.close();
    });

    testWidgets('ҳамма тингловчи кетгач манба ёпилади, янгиси келса қайта очилади', (t) async {
      var opens = 0;
      var closes = 0;
      final s = restartableBroadcast<int>(() {
        opens++;
        final c = StreamController<int>(onCancel: () => closes++);
        c.add(1);
        return c.stream;
      });
      await t.pumpWidget(MaterialApp(home: StreamBuilder<int>(stream: s, builder: (_, __) => const SizedBox())));
      await t.pump();
      expect(opens, 1);
      await t.pumpWidget(const MaterialApp(home: SizedBox()));
      await t.pump();
      expect(closes, 1);
      await t.pumpWidget(MaterialApp(home: StreamBuilder<int>(stream: s, builder: (_, __) => const SizedBox())));
      await t.pump();
      expect(opens, 2);
    });

    testWidgets('Firestore каби: қиймат + давом этувчи оқим', (t) async {
      final c = StreamController<int>();
      final s = restartableBroadcast<int>(() => c.stream);
      await t.pumpWidget(host(s));
      c.add(5);
      await t.pump();
      expect(find.text('v5'), findsOneWidget);
      c.add(6);
      await t.pump();
      await t.pump(const Duration(milliseconds: 20));
      expect(find.text('v6'), findsOneWidget);
      await c.close();
    });
  });

  test('оқимни кетма-кет икки марта тинглаш мумкин', () async {
    SharedPreferences.setMockInitialValues({});
    final s = walletBalanceStream();
    expect(await s.toList(), isEmpty);
    // Манба тугаган бўлса ҳам иккинчи тингловчи хато бермайди.
    await expectLater(s, emitsDone);
  });
}
