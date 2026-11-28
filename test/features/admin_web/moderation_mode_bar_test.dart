// Yagona «АВТО / ҚЎЛДА» paneli va server registri talqini (ega 2026-11-28, audit C-1).
import 'dart:async';

import 'package:ava_gurlan/features/admin_web/services/admin_moderation_modes_service.dart';
import 'package:ava_gurlan/features/admin_web/widgets/moderation_mode_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ModerationModeInfo — server isModeAuto bilan bir xil', () {
    test('defaultOn=false: faqat aniq true yoqadi', () {
      const info = ModerationModeInfo(mode: 'tv', field: 'tvAutoApprove', defaultOn: false);
      expect(info.effective({'tvAutoApprove': true}), isTrue);
      for (final s in <Map<String, dynamic>?>[
        null,
        {},
        {'tvAutoApprove': false},
        {'tvAutoApprove': 'true'},
        {'tvAutoApprove': 1},
        {'tvAutoApprove': null},
        {'marketAutoApprove': true},
      ]) {
        expect(info.effective(s), isFalse, reason: '$s');
      }
    });

    test('defaultOn=true (realty): faqat aniq false o\'chiradi; yo\'q/null — AVTO', () {
      const info = ModerationModeInfo(mode: 'realty', field: 'realtyAutoApprove', defaultOn: true);
      expect(info.effective({'realtyAutoApprove': false}), isFalse);
      for (final s in <Map<String, dynamic>?>[null, {}, {'realtyAutoApprove': true}, {'realtyAutoApprove': null}]) {
        expect(info.effective(s), isTrue, reason: '$s');
      }
    });

    test('fromMap: buzuq yozuv — null', () {
      expect(ModerationModeInfo.fromMap({'mode': 'tv', 'field': 'tvAutoApprove', 'defaultOn': false})?.field,
          'tvAutoApprove');
      expect(ModerationModeInfo.fromMap({'mode': '', 'field': 'x'}), isNull);
      expect(ModerationModeInfo.fromMap('tv'), isNull);
      expect(ModerationModeInfo.fromMap({'mode': 'tv'}), isNull);
    });
  });

  group('ModerationModeBar', () {
    late StreamController<bool> ctrl;
    late List<bool> sets;
    Object? failWith;

    setUp(() {
      ctrl = StreamController<bool>.broadcast();
      sets = [];
      failWith = null;
    });
    tearDown(() => ctrl.close());

    Future<void> pump(WidgetTester tester, {bool confirm = false}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ModerationModeBar(
            mode: ModerationMode.tv,
            keyPrefix: 'mm',
            onLabel: 'ON-LABEL',
            offLabel: 'OFF-LABEL',
            confirmTitle: confirm ? 'Ишончингиз комилми?' : null,
            watch: () => ctrl.stream,
            set: (v) async {
              sets.add(v);
              final f = failWith;
              if (f != null) throw f;
              ctrl.add(v);
            },
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('qiymat kelmaguncha — ҚЎЛДА; АВТО → set(true); ҚЎЛДА → set(false)', (tester) async {
      await pump(tester);
      expect(find.text('OFF-LABEL'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mm_auto_on')));
      await tester.pumpAndSettle();
      expect(sets, [true]);
      expect(find.text('ON-LABEL'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('mm_auto_on'))).onPressed, isNull);
      await tester.tap(find.byKey(const ValueKey('mm_auto_manual')));
      await tester.pumpAndSettle();
      expect(sets, [true, false]);
      expect(find.text('OFF-LABEL'), findsOneWidget);
    });

    testWidgets('tasdiq oynasi: bekor — yozuv yo\'q; «Ёқиш» — set(true)', (tester) async {
      await pump(tester, confirm: true);
      await tester.tap(find.byKey(const ValueKey('mm_auto_on')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Бекор'));
      await tester.pumpAndSettle();
      expect(sets, isEmpty);
      await tester.tap(find.byKey(const ValueKey('mm_auto_on')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mm_auto_confirm')));
      await tester.pumpAndSettle();
      expect(sets, [true]);
    });

    testWidgets('yozish xatosi — qisqa matn + kod, holat o\'zgarmaydi', (tester) async {
      await pump(tester);
      ctrl.add(false);
      await tester.pump();
      failWith = StateError('boom');
      await tester.tap(find.byKey(const ValueKey('mm_auto_on')));
      await tester.pumpAndSettle();
      expect(sets, [true]);
      expect(find.textContaining('CLIENT_ERROR'), findsOneWidget);
      expect(find.text('OFF-LABEL'), findsOneWidget);
    });

    testWidgets('oqim xatosi (masalan MODE_UNKNOWN) — tugmalar yo\'q, xabar', (tester) async {
      await pump(tester);
      ctrl.addError(StateError('MODE_UNKNOWN'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('mm_auto_on')), findsNothing);
      expect(find.textContaining('юклаб бўлмади'), findsOneWidget);
    });
  });
}
