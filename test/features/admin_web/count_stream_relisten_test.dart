import 'dart:async';

import 'package:ava_gurlan/features/admin_web/utils/count_stream_sum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Регрессия (эга скриншоти, 2026-10-08): admin сайдбарида «Бозорлар ва
/// эълонлар» гуруҳида «Аҳоли бозори» дан кейин катта кулранг блок чиқиб,
/// қолган бўлимлар йўқоларди.
///
/// Symptom: release'даги ErrorWidget (кулранг, 100000 px баланд) «Улгуржи
/// бозор» қатори ўрнида.
/// Root cause: «Улгуржи бозор» нишони `sumCountStreams` қайтарган БИР
/// МАРТАЛИК (single-subscription) оқим эди. Сайдбар — `ListView(children:)`:
/// экрандан чиққан қатор элементи ўчирилади, қайтганда ЎША виджетдан
/// янгиси қурилади ва `StreamBuilder` ўша оқимни ИККИНЧИ марта тинглайди →
/// `Bad state: Stream has already been listened to.` initState'да синхрон
/// отилади. Бошқа нишонлар — Firestore оқимлари, қайта тингланади.
/// Fix: `sumCountStreams` ҳар тингловчига алоҳида обуна беради
/// (`Stream.multi`).
void main() {
  group('sumCountStreams — қайта тинглаш', () {
    test('бир оқимни икки марта тинглаш мумкин (cancel → listen)', () async {
      final a = StreamController<int>.broadcast();
      final b = StreamController<int>.broadcast();
      final s = sumCountStreams([a.stream, b.stream]);

      final first = <int>[];
      final sub1 = s.listen(first.add);
      a.add(2);
      b.add(3);
      await pumpEventQueue();
      expect(first.last, 5);
      await sub1.cancel();

      // Аввал бу ерда StateError отиларди.
      final second = <int>[];
      final sub2 = s.listen(second.add);
      a.add(4);
      await pumpEventQueue();
      expect(second.last, 4, reason: 'янги обуна 0 дан бошлайди');
      b.add(1);
      await pumpEventQueue();
      expect(second.last, 5);
      await sub2.cancel();
      await a.close();
      await b.close();
    });

    test('бир вақтда икки тингловчи — ҳар бири ўз йиғиндиси', () async {
      final a = StreamController<int>.broadcast();
      final ten = StreamController<int>.broadcast(onListen: () {});
      final s = sumCountStreams([a.stream, ten.stream]);
      final x = <int>[];
      final y = <int>[];
      final s1 = s.listen(x.add);
      final s2 = s.listen(y.add);
      ten.add(10);
      a.add(1);
      await pumpEventQueue();
      expect(x.last, 11);
      expect(y.last, 11);
      await s1.cancel();
      await s2.cancel();
      await a.close();
      await ten.close();
    });

    test('cancel ички обуналарни ёпади (тингловчи осилиб қолмайди)', () async {
      var listeners = 0;
      final inner = StreamController<int>.broadcast(
        onListen: () => listeners++,
        onCancel: () => listeners--,
      );
      final other = StreamController<int>.broadcast();
      final s = sumCountStreams([inner.stream, other.stream]);
      final sub = s.listen((_) {});
      await pumpEventQueue();
      expect(listeners, 1);
      await sub.cancel();
      expect(listeners, 0);
      await inner.close();
      await other.close();
    });
  });

  testWidgets(
      'ListView: нишонли қатор экрандан чиқиб қайтганда хато йўқ '
      '(сайдбардаги кулранг блок)', (tester) async {
    final src = StreamController<int>.broadcast();
    addTearDown(src.close);
    // Сайдбардаги каби: виджетлар рўйхати БИР МАРТА қурилади, оқим объекти
    // виджет ичида сақланади.
    // Ички оқимлар — production'даги Firestore snapshots() каби қайта
    // тингланадиган (broadcast).
    final badge = sumCountStreams([src.stream, src.stream.map((v) => v)]);
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          height: 300,
          child: ListView(
            controller: controller,
            children: [
              for (var i = 0; i < 40; i++)
                SizedBox(
                  height: 60,
                  child: i == 20
                      ? StreamBuilder<int>(
                          stream: badge,
                          builder: (_, s) => Text('badge ${s.data ?? 0}'),
                        )
                      : Text('row $i'),
                ),
            ],
          ),
        ),
      ),
    ));

    // 1) Пастга — нишонли қатор биринчи марта қурилади.
    controller.jumpTo(20 * 60.0);
    await tester.pumpAndSettle();
    expect(find.textContaining('badge'), findsOneWidget);
    // 2) Юқорига — кеш чегарасидан ташқарида, элемент ўчирилади.
    controller.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.textContaining('badge'), findsNothing);
    // 3) Яна пастга — ўша оқим қайта тингланади.
    controller.jumpTo(20 * 60.0);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.textContaining('badge'), findsOneWidget);
  });
}
