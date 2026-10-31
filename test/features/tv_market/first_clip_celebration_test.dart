// Эга, 2026-10-31: биринчи AVAGram видеоси жойланганда конфетти — эга учун БИР МАРТА.
// `maybeCelebrateFirstClip` — жойлаш экранидаги муваффақият йўлида чақирилади (snack'дан кейин,
// превью ва `pop(true)` дан олдин). Локализация делегати уланмаган: `context.tr` калитни қайтаради.

import 'dart:async';

import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/tv_market/screens/tv_publish_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Harness {
  final results = <bool>[];
  var serverCalls = 0;
}

/// Тугма босилса — helper чақирилади; натижа [h.results] га тушади.
Future<_Harness> _pump(
  WidgetTester t, {
  required String phone,
  required String clipId,
  required bool active,
  required Future<List<String>> Function() server,
  Duration timeout = const Duration(seconds: 4),
}) async {
  final h = _Harness();
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Builder(
      builder: (context) => Scaffold(
        body: ElevatedButton(
          onPressed: () async {
            h.results.add(await maybeCelebrateFirstClip(
              context,
              ownerPhone: phone,
              clipId: clipId,
              active: active,
              timeout: timeout,
              ownerClipIds: () {
                h.serverCalls++;
                return server();
              },
            ));
          },
          child: const Text('publish'),
        ),
      ),
    ),
  ));
  return h;
}

Future<void> _publish(WidgetTester t) async {
  await t.tap(find.text('publish'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _closeIfOpen(WidgetTester t) async {
  final ok = find.byKey(const ValueKey('celebration_ok'));
  if (ok.evaluate().isNotEmpty) {
    await t.pumpAndSettle();
    await t.tap(ok);
  }
  await t.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('биринчи ФАОЛ видео (серверда фақат шу клип) — табрик: калитлар, белги, конфетти; тугма ёпади', (t) async {
    final h = await _pump(t, phone: '998901112233', clipId: 'c1', active: true, server: () async => ['c1']);
    await _publish(t);

    expect(find.text('tv_first_clip_title'), findsOneWidget);
    expect(find.text('tv_first_clip_sub'), findsOneWidget);
    expect(find.text('tv_first_clip_continue'), findsOneWidget);
    expect(find.byIcon(Icons.videocam_rounded), findsOneWidget);
    expect(find.byKey(const ValueKey('celebration_confetti')), findsOneWidget);
    expect(h.results, isEmpty, reason: 'ойна ёпилгунча кутади (кейин превью ва pop)');

    await _closeIfOpen(t);
    expect(find.text('tv_first_clip_title'), findsNothing);
    expect(h.results, [true]);
  });

  testWidgets('иккинчи жойлаш (шу эга) — табрик йўқ, сервер ҳам сўралмайди', (t) async {
    final h = await _pump(t, phone: '998901112233', clipId: 'c1', active: true, server: () async => ['c1']);
    await _publish(t);
    await _closeIfOpen(t);
    expect(h.results, [true]);

    await _publish(t);
    await t.pumpAndSettle();
    expect(find.text('tv_first_clip_title'), findsNothing);
    expect(h.results, [true, false]);
    expect(h.serverCalls, 1, reason: '«бир марта» белгиси қўйилгач қўшимча ўқиш йўқ');
  });

  testWidgets('текширувга кетган (pending) — табрик йўқ ва «бир марта» белгиси САРФЛАНМАЙДИ', (t) async {
    final pending = await _pump(t, phone: '998901112233', clipId: 'c1', active: false, server: () async => ['c1']);
    await _publish(t);
    await t.pumpAndSettle();
    expect(find.text('tv_first_clip_title'), findsNothing);
    expect(pending.results, [false]);
    expect(pending.serverCalls, 0);

    // Кейинги (энди фаол) жойлаш ҳали ҳам биринчи бўлиши мумкин — белги ишлатилмаган.
    final active = await _pump(t, phone: '998901112233', clipId: 'c2', active: true, server: () async => ['c2']);
    await _publish(t);
    expect(find.text('tv_first_clip_title'), findsOneWidget);
    await _closeIfOpen(t);
    expect(active.results, [true]);
  });

  testWidgets('эски муаллиф (серверда бошқа клипи бор) — «биринчи» деб чиқмайди ва кейин ҳам чиқмайди', (t) async {
    final h = await _pump(t, phone: '998905556677', clipId: 'new', active: true, server: () async => ['new', 'old']);
    await _publish(t);
    await t.pumpAndSettle();
    expect(find.text('tv_first_clip_title'), findsNothing);
    expect(h.results, [false]);

    await _publish(t);
    await t.pumpAndSettle();
    expect(find.text('tv_first_clip_title'), findsNothing);
    expect(h.serverCalls, 1);
  });

  testWidgets('чегара: сервер рўйхатида янги клип ҳали йўқ, лекин бошқаси бор — табрик йўқ', (t) async {
    final h = await _pump(t, phone: '998905556677', clipId: 'new', active: true, server: () async => ['old']);
    await _publish(t);
    await t.pumpAndSettle();
    expect(find.text('tv_first_clip_title'), findsNothing);
    expect(h.results, [false]);
  });

  testWidgets('чегара: сервер рўйхати бўш (кеш кечикди) — бошқа клип йўқ, табрик бор', (t) async {
    final h = await _pump(t, phone: '998905556677', clipId: 'new', active: true, server: () async => const []);
    await _publish(t);
    expect(find.text('tv_first_clip_title'), findsOneWidget);
    await _closeIfOpen(t);
    expect(h.results, [true]);
  });

  testWidgets('сервер текшируви хато берди — табриксиз, хато ташқарига чиқмайди', (t) async {
    final h = await _pump(t,
        phone: '998905556677', clipId: 'new', active: true, server: () async => throw StateError('offline'));
    await _publish(t);
    await t.pumpAndSettle();
    expect(find.text('tv_first_clip_title'), findsNothing);
    expect(h.results, [false]);
    expect(t.takeException(), isNull);
  });

  testWidgets('сервер текшируви кечикди (timeout) — табриксиз, жойлаш оқими осилиб қолмайди', (t) async {
    final never = Completer<List<String>>();
    final h = await _pump(t,
        phone: '998905556677',
        clipId: 'new',
        active: true,
        timeout: const Duration(seconds: 2),
        server: () => never.future);
    await _publish(t);
    await t.pump(const Duration(seconds: 3));
    await t.pumpAndSettle();
    expect(find.text('tv_first_clip_title'), findsNothing);
    expect(h.results, [false]);
  });

  testWidgets('чегара: бошқа эга (бошқа телефон) — ўз «биринчи»си алоҳида', (t) async {
    final a = await _pump(t, phone: '998901112233', clipId: 'a1', active: true, server: () async => ['a1']);
    await _publish(t);
    await _closeIfOpen(t);
    expect(a.results, [true]);

    final b = await _pump(t, phone: '998907778899', clipId: 'b1', active: true, server: () async => ['b1']);
    await _publish(t);
    expect(find.text('tv_first_clip_title'), findsOneWidget);
    await _closeIfOpen(t);
    expect(b.results, [true]);
  });

  testWidgets('чегара: телефон ёки клип id бўш — табрик йўқ (белги ҳам қўйилмайди)', (t) async {
    final h = await _pump(t, phone: '', clipId: 'c1', active: true, server: () async => ['c1']);
    await _publish(t);
    await t.pumpAndSettle();
    expect(h.results, [false]);
    expect(h.serverCalls, 0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });
}
