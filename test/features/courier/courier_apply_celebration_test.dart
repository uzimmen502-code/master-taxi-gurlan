import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/courier/widgets/courier_apply_flow.dart';
import 'package:ava_gurlan/repositories/courier_capability_repository.dart';
import 'package:ava_gurlan/shared/widgets/celebration_dialog.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Эга, 2026-10-31: курьер тасдиқланганда табрик — шу телефон учун БИР МАРТА;
/// «Курьер панели» босилгач панел очилади. Ариза юборилди / хато — snack.
/// Локализация делегати уланмаган: `context.tr` калитнинг ўзини қайтаради.
class _FakeRepo implements CourierCapabilityRepository {
  _FakeRepo(this.status, {this.error});

  final String status;
  final Object? error;
  int calls = 0;

  @override
  Future<String> apply({String requestId = ''}) async {
    calls++;
    if (error != null) throw error!;
    return status;
  }

  @override
  Future<String> fetchStatus(String uid) async => status;
}

const _phone = '+998 90 111 22 33';
const _onceKey = 'courier_approved_998901112233';

class _Harness {
  CourierApplyResult? result;
  int panelOpened = 0;
}

Future<_Harness> _run(WidgetTester t, _FakeRepo repo) async {
  final h = _Harness();
  await t.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () async {
            h.result = await runCourierApplyFlow(
              context,
              repository: repo,
              openPanel: (_) async => h.panelOpened++,
            );
          },
          child: const Text('go'),
        ),
      ),
    ),
  ));
  await t.tap(find.text('go'));
  await t.pumpAndSettle();
  // Тасдиқ ойнаси: «Ариза бериш».
  await t.tap(find.text('courier_apply_confirm'));
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  return h;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'user_phone': _phone}));

  testWidgets('биринчи тасдиқ: табрик (сарлавҳа, изоҳ, «Курьер панели»), snack йўқ', (t) async {
    final h = await _run(t, _FakeRepo('trial'));
    expect(find.text('courier_apply_approved_title'), findsOneWidget);
    expect(find.text('courier_apply_approved_sub'), findsOneWidget);
    expect(find.text('home_create_courier_open'), findsOneWidget);
    expect(find.text('courier_apply_approved'), findsNothing, reason: 'табрик snack ўрнида');
    expect(h.panelOpened, 0, reason: 'панел тугма босилгунча очилмайди');

    await t.tap(find.byKey(const ValueKey('celebration_ok')));
    await t.pumpAndSettle();
    expect(find.text('courier_apply_approved_title'), findsNothing, reason: 'ойна ёпилди');
    expect(h.panelOpened, 1, reason: '«Курьер панели» — оқим панелни очади');
    expect(h.result?.status, 'trial');
    expect(h.result?.failed, isFalse);
  });

  testWidgets('иккинчи марта (шу телефон): табрик йўқ — аввалги snack, панел очилмайди', (t) async {
    SharedPreferences.setMockInitialValues({
      'user_phone': _phone,
      'celebrated_v1_$_onceKey': true,
    });
    final h = await _run(t, _FakeRepo('approved'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('celebration_ok')), findsNothing);
    expect(find.text('courier_apply_approved'), findsOneWidget);
    expect(h.panelOpened, 0);
    expect(h.result?.status, 'approved');
  });

  testWidgets('чегара: ариза юборилди (applied) — snack, табрик йўқ, «бир марта» сарфланмайди', (t) async {
    final h = await _run(t, _FakeRepo(CourierCapabilityRepository.applied));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('celebration_ok')), findsNothing);
    expect(find.text('courier_apply_sent'), findsOneWidget);
    expect(h.panelOpened, 0);
    expect(await CelebrationOnce.claim(_onceKey), isTrue, reason: 'кейинги ҳақиқий тасдиқда табрик чиқади');
  });

  testWidgets('чегара: тўхтатилган (suspended) — табрик эмас, аввалги snack', (t) async {
    final h = await _run(t, _FakeRepo('suspended'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('celebration_ok')), findsNothing);
    expect(find.text('courier_apply_approved'), findsOneWidget);
    expect(h.panelOpened, 0);
    expect(await CelebrationOnce.claim(_onceKey), isTrue);
  });

  testWidgets('чегара: сервер хатоси — хато snack, табрик йўқ', (t) async {
    final repo = _FakeRepo('', error: FirebaseFunctionsException(message: 'x', code: 'internal'));
    final h = await _run(t, repo);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('celebration_ok')), findsNothing);
    expect(find.text('courier_apply_failed'), findsOneWidget);
    expect(h.result?.failed, isTrue);
    expect(h.panelOpened, 0);
    expect(await CelebrationOnce.claim(_onceKey), isTrue);
  });

  testWidgets('чегара: телефон номаълум — табрик йўқ (объектга боғлаб бўлмайди), snack', (t) async {
    SharedPreferences.setMockInitialValues({});
    final h = await _run(t, _FakeRepo('trial'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('celebration_ok')), findsNothing);
    expect(find.text('courier_apply_approved'), findsOneWidget);
    expect(h.panelOpened, 0);
  });

  testWidgets('бекор қилинса — сўров йўқ, хабар йўқ', (t) async {
    final repo = _FakeRepo('trial');
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => runCourierApplyFlow(context, repository: repo, openPanel: (_) async {}),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    await t.tap(find.text('cancel'));
    await t.pumpAndSettle();
    expect(repo.calls, 0);
    expect(find.byKey(const ValueKey('celebration_ok')), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });
}
