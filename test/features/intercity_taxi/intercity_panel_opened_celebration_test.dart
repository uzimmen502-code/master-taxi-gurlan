import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/intercity_taxi/driver/screens/intercity_driver_panel_screen.dart';
import 'package:ava_gurlan/shared/widgets/celebration_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Эга, 2026-10-31: шаҳарлараро ҳайдовчи панели БИРИНЧИ марта очилганда табрик
/// (шу телефон учун бир марта); кейинги очилишлар — аввалги «Панел очилди» snack.
/// Локализация делегати уланмаган: `context.tr` калитнинг ўзини қайтаради.
Future<void> _pump(WidgetTester t, String phone) async {
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showIntercityPanelOpenedFeedback(context, phone: phone),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('open'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('биринчи марта: табрик (сарлавҳа, изоҳ, «Давом этиш»), snack йўқ; тугма ёпади', (t) async {
    await _pump(t, '998901112233');
    expect(find.text('intercity_open_panel_done_title'), findsOneWidget);
    expect(find.text('intercity_open_panel_done_sub'), findsOneWidget);
    expect(find.text('celebration_continue'), findsOneWidget);
    expect(find.text('intercity_open_panel_done'), findsNothing);

    await t.tap(find.byKey(const ValueKey('celebration_ok')));
    await t.pumpAndSettle();
    expect(find.text('intercity_open_panel_done_title'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('иккинчи марта (шу телефон, 9 рақамли ёзуви ҳам): ойна йўқ — аввалги snack', (t) async {
    SharedPreferences.setMockInitialValues({'celebrated_v1_intercity_panel_opened_998901112233': true});
    await _pump(t, '901112233');
    expect(find.byKey(const ValueKey('celebration_ok')), findsNothing);
    expect(find.text('intercity_open_panel_done'), findsOneWidget);
    await t.pumpAndSettle(const Duration(seconds: 5));
  });

  testWidgets('чегара: бошқа телефон — мустақил (у ҳам бир марта табрикланади)', (t) async {
    SharedPreferences.setMockInitialValues({'celebrated_v1_intercity_panel_opened_998901112233': true});
    await _pump(t, '998935556677');
    expect(find.text('intercity_open_panel_done_title'), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('celebration_ok')));
    await t.pumpAndSettle();
  });

  testWidgets('чегара: телефон номаълум — табрик йўқ, snack; «бир марта» сарфланмайди', (t) async {
    await _pump(t, '');
    expect(find.byKey(const ValueKey('celebration_ok')), findsNothing);
    expect(find.text('intercity_open_panel_done'), findsOneWidget);
    expect(await CelebrationOnce.claim('intercity_panel_opened_'), isTrue);
    await t.pumpAndSettle(const Duration(seconds: 5));
  });
}
