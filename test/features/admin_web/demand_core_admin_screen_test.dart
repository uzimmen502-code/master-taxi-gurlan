// «Талаб ядроси» админ экрани: ҳудудлар рўйхати, тугма блоклаш, тасдиқ диалоги,
// сервер хатоси, push чегараси. Firebase йўқ: loader/setter ТАШҚАРИДАН берилади.
import 'package:ava_gurlan/features/admin_web/screens/demand_core_admin_screen.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _row(
  String id,
  String name, {
  String state = 'off',
  int providers = 5,
  Object? minScore,
  List<String>? errors,
}) =>
    {
      'regionId': id,
      'name': name,
      'state': state,
      'providers': providers,
      'ready': providers >= 5,
      'minScore': minScore,
      'ownConfig': state != 'off',
      if (errors != null) 'configErrors': errors,
    };

Map<String, dynamic> _overview({
  List<Map<String, dynamic>>? rows,
  Object? minScoreAll,
  bool kill = false,
  List<Map<String, dynamic>>? audit,
}) =>
    {
      'ok': true,
      'module': 'service',
      'mode': 'quote',
      'minProviders': 5,
      'minScoreAll': minScoreAll,
      'globalKill': {'active': kill, 'reason': kill ? 'incident' : ''},
      'rows': rows ??
          [
            _row('xorazm', 'Хоразм'),
            _row('andijon', 'Андижон', providers: 2),
          ],
      'audit': audit ?? <Map<String, dynamic>>[],
    };

class _Harness {
  _Harness(this.data);
  Map<String, dynamic> data;
  int loads = 0;
  final List<Map<String, dynamic>> calls = [];
  Object? setterError;

  Future<Map<String, dynamic>> loader() async {
    loads += 1;
    return data;
  }

  Future<Map<String, dynamic>> setter(Map<String, dynamic> payload) async {
    calls.add(payload);
    if (setterError != null) throw setterError!;
    return {'ok': true, 'changed': true};
  }
}

Future<void> _pump(WidgetTester tester, _Harness h) async {
  await tester.binding.setSurfaceSize(const Size(900, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: DemandCoreAdminScreen(loader: h.loader, setter: h.setter),
    ),
  ));
  await tester.pumpAndSettle();
}

Finder _btn(String region, String target) => find.byKey(ValueKey('btn_${region}_$target'));

bool _enabled(WidgetTester tester, Finder f) {
  final w = tester.widget(f);
  if (w is OutlinedButton) return w.onPressed != null;
  if (w is FilledButton) return w.onPressed != null;
  throw StateError('кутилмаган тугма тури: ${w.runtimeType}');
}

void main() {
  testWidgets('ҳудудлар, ҳолат ва таклифчилар сони кўрсатилади', (tester) async {
    await _pump(tester, _Harness(_overview()));
    expect(find.text('Хоразм'), findsOneWidget);
    expect(find.text('Андижон'), findsOneWidget);
    expect(find.byKey(const ValueKey('providers_xorazm')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('providers_xorazm'))).data,
      '5 / 5',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('providers_andijon'))).data,
      '2 / 5',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('state_xorazm'))).data,
      'Ўчиқ',
    );
  });

  testWidgets('тугмалар: ҳозирги ҳолат ва етарли эмас ҳудуд хира, тайёри — фаол', (tester) async {
    await _pump(tester, _Harness(_overview()));
    // Хоразм: off (ҳозирги), shadow — мумкин (5/5), push — чегара йўқ.
    expect(_enabled(tester, _btn('xorazm', 'off')), isFalse);
    expect(_enabled(tester, _btn('xorazm', 'shadow')), isTrue);
    expect(_enabled(tester, _btn('xorazm', 'push')), isFalse);
    // Андижон: 2/5 — shadow ва push хира.
    expect(_enabled(tester, _btn('andijon', 'shadow')), isFalse);
    expect(_enabled(tester, _btn('andijon', 'push')), isFalse);
  });

  testWidgets('чегара ўрнатилган бўлса push тугмаси фаол', (tester) async {
    await _pump(
      tester,
      _Harness(_overview(minScoreAll: 0.75, rows: [
        _row('xorazm', 'Хоразм', state: 'shadow', minScore: 0.75),
      ])),
    );
    expect(_enabled(tester, _btn('xorazm', 'push')), isTrue);
    expect(_enabled(tester, _btn('xorazm', 'off')), isTrue);
    expect(_enabled(tester, _btn('xorazm', 'shadow')), isFalse, reason: 'ҳозирги ҳолат');
  });

  testWidgets('Shadow босилса тасдиқ диалоги чиқади; «Ҳа» -> setter ва қайта юклаш', (tester) async {
    final h = _Harness(_overview());
    await _pump(tester, h);
    await tester.tap(_btn('xorazm', 'shadow'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('confirm_yes')), findsOneWidget);
    expect(find.textContaining('Хоразм'), findsWidgets);
    expect(h.calls, isEmpty, reason: 'тасдиқдан олдин ҳеч нарса юборилмайди');

    await tester.tap(find.byKey(const ValueKey('confirm_yes')));
    await tester.pumpAndSettle();

    expect(h.calls, [
      {'module': 'service', 'regionId': 'xorazm', 'state': 'shadow'},
    ]);
    expect(h.loads, 2, reason: 'ўзгаришдан кейин рўйхат қайта юкланади');
  });

  testWidgets('«Йўқ» -> setter чақирилмайди', (tester) async {
    final h = _Harness(_overview());
    await _pump(tester, h);
    await tester.tap(_btn('xorazm', 'shadow'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm_no')));
    await tester.pumpAndSettle();
    expect(h.calls, isEmpty);
    expect(h.loads, 1);
  });

  testWidgets('сервер рад этса — тушунарли хабар, экран ишлайверади', (tester) async {
    final h = _Harness(_overview())
      ..setterError = FirebaseFunctionsException(
        message: 'Hududda ishlay oladigan taklifchi 4 ta, kamida 5 ta kerak',
        code: 'failed-precondition',
        details: {'reason': 'not_enough_providers'},
      );
    await _pump(tester, h);
    await tester.tap(_btn('xorazm', 'shadow'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm_yes')));
    await tester.pumpAndSettle();

    expect(find.textContaining('таклифчи етарли эмас'), findsOneWidget);
    expect(find.text('Хоразм'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('push чегараси: хато киритиш (90) рад, 0,75 тўғри юборилади', (tester) async {
    final h = _Harness(_overview());
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('btn_edit_min_score')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('min_score_field')), '90');
    await tester.tap(find.byKey(const ValueKey('min_score_save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('0.01'), findsWidgets);
    expect(h.calls, isEmpty, reason: 'нотўғри қиймат юборилмайди');

    await tester.enterText(find.byKey(const ValueKey('min_score_field')), '0,75');
    await tester.tap(find.byKey(const ValueKey('min_score_save')));
    await tester.pumpAndSettle();
    expect(h.calls, [
      {'module': 'service', 'regionId': 'all', 'minScore': 0.75},
    ]);
  });

  testWidgets('push чегарасини ўчириш (null) юборилади', (tester) async {
    final h = _Harness(_overview(minScoreAll: 0.75));
    await _pump(tester, h);
    await tester.tap(find.byKey(const ValueKey('btn_edit_min_score')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('min_score_clear')));
    await tester.pumpAndSettle();
    expect(h.calls, [
      {'module': 'service', 'regionId': 'all', 'minScore': null},
    ]);
  });

  testWidgets('чегара ўрнатилмаган бўлса шу ёзилади', (tester) async {
    await _pump(tester, _Harness(_overview()));
    expect(find.byKey(const ValueKey('min_score_state')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('min_score_state'))).data,
      contains('ўрнатилмаган'),
    );
  });

  testWidgets('чегара ўрнатилган бўлса қиймат кўрсатилади', (tester) async {
    await _pump(tester, _Harness(_overview(minScoreAll: 0.75)));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('min_score_state'))).data,
      contains('0.75'),
    );
  });

  testWidgets('глобал kill фаол бўлса қизил огоҳлантириш', (tester) async {
    await _pump(tester, _Harness(_overview(kill: true)));
    expect(find.byKey(const ValueKey('global_kill_banner')), findsOneWidget);
    expect(find.textContaining('incident'), findsOneWidget);
  });

  testWidgets('глобал kill йўқ бўлса огоҳлантириш чиқмайди', (tester) async {
    await _pump(tester, _Harness(_overview()));
    expect(find.byKey(const ValueKey('global_kill_banner')), findsNothing);
  });

  testWidgets('аудит: ёзув, ҳудуд номи ва ниқобланган телефон кўринади', (tester) async {
    await _pump(tester, _Harness(_overview(audit: [
      {
        'id': 'a1',
        'at': 1760954400000,
        'actor': '9989099****01',
        'regionId': 'xorazm',
        'from': {'state': 'off', 'minScore': null},
        'to': {'state': 'shadow', 'minScore': null},
      },
    ])));
    expect(find.byKey(const ValueKey('audit_a1')), findsOneWidget);
    expect(find.textContaining('9989099****01'), findsOneWidget);
    expect(find.textContaining('Ўчиқ → Shadow'), findsOneWidget);
  });

  testWidgets('аудит бўш бўлса «ҳали ўзгариш йўқ»', (tester) async {
    await _pump(tester, _Harness(_overview()));
    expect(find.byKey(const ValueKey('audit_empty')), findsOneWidget);
  });

  testWidgets('конфиг хатоси бор ҳудудда огоҳлантириш', (tester) async {
    await _pump(tester, _Harness(_overview(rows: [
      _row('xorazm', 'Хоразм', state: 'shadow', errors: ['weights нотўғри']),
    ])));
    expect(find.textContaining('weights нотўғри'), findsOneWidget);
  });

  testWidgets('юклаш хатоси: хабар ва «Қайта уриниш»', (tester) async {
    var n = 0;
    Future<Map<String, dynamic>> loader() async {
      n += 1;
      if (n == 1) throw StateError('permission-denied');
      return _overview();
    }

    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DemandCoreAdminScreen(
          loader: loader,
          setter: (_) async => {'ok': true},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('retry')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('retry')));
    await tester.pumpAndSettle();
    expect(find.text('Хоразм'), findsOneWidget);
    expect(n, 2);
  });

  testWidgets('тор экран (320) ва катта шрифт: overflow йўқ', (tester) async {
    final h = _Harness(_overview(audit: [
      {
        'id': 'a1',
        'at': 1760954400000,
        'actor': '9989099****01',
        'regionId': 'toshkent_viloyati',
        'from': {'state': 'matching_off', 'minScore': null},
        'to': {'state': 'shadow', 'minScore': 0.75},
      },
    ]));
    await tester.binding.setSurfaceSize(const Size(320, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(320, 2400), textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: DemandCoreAdminScreen(loader: h.loader, setter: h.setter),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
