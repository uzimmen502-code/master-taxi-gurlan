import 'package:ava_gurlan/features/courier/widgets/courier_profile_entry.dart';
import 'package:ava_gurlan/repositories/courier_capability_repository.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// D-15.5 (эга қарори 2026-10-08): профилда курьерлик ҲУҚУҚ ҳолатидан
/// кўрсатилади, `users.role`дан эмас.
///
/// Локализация делегати АТАЙЛАБ уланмаган: `context.tr` калитнинг ўзини
/// қайтаради — тест илова тилидан мустақил.
class _FakeRepo implements CourierCapabilityRepository {
  _FakeRepo({this.status = 'not_registered', this.applyResult = 'applied'});

  String status;
  String applyResult;
  Object? applyError;
  Object? fetchError;
  int applyCalls = 0;

  @override
  Future<String> fetchStatus(String uid) async {
    if (fetchError != null) throw fetchError!;
    return status;
  }

  @override
  Future<String> apply() async {
    applyCalls += 1;
    if (applyError != null) throw applyError!;
    return applyResult;
  }
}

Widget _button({
  required String label,
  required IconData icon,
  required Color color,
  required VoidCallback onTap,
}) =>
    ElevatedButton(onPressed: onTap, child: Text(label));

Future<void> _pump(
  WidgetTester tester,
  _FakeRepo repo, {
  bool legacy = false,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: CourierProfileEntry(
        userId: '998901110001',
        legacyCourierRole: legacy,
        panelButton: _button,
        repository: repo,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

const _apply = 'courier_apply_button';
const _panel = 'profile_courier_panel';
const _pending = 'courier_apply_pending';
const _suspended = 'courier_suspended_note';

Future<void> _applyAndConfirm(WidgetTester tester) async {
  await tester.tap(find.text(_apply));
  await tester.pumpAndSettle();
  await tester.tap(find.text('courier_apply_confirm'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('рўйхатдан ўтмаган — фақат «Курьер бўлиш», панел ЙЎҚ',
      (tester) async {
    await _pump(tester, _FakeRepo());
    expect(find.text(_apply), findsOneWidget);
    expect(find.text(_panel), findsNothing);
    expect(find.text(_pending), findsNothing);
  });

  testWidgets('мануал: ариза → «кўриб чиқилмоқда», панел ОЧИЛМАЙДИ',
      (tester) async {
    final repo = _FakeRepo(applyResult: 'applied');
    await _pump(tester, repo);
    await _applyAndConfirm(tester);

    expect(repo.applyCalls, 1);
    expect(find.text(_pending), findsOneWidget);
    expect(find.text(_panel), findsNothing, reason: 'админ тасдиғигача иш йўқ');
    expect(find.text(_apply), findsNothing, reason: 'қайта ариза тугмаси йўқ');
    expect(find.text('courier_apply_sent'), findsOneWidget);
  });

  testWidgets('диалогда «Бекор» — сервер чақирилмайди', (tester) async {
    final repo = _FakeRepo();
    await _pump(tester, repo);
    await tester.tap(find.text(_apply));
    await tester.pumpAndSettle();
    await tester.tap(find.text('cancel'));
    await tester.pumpAndSettle();

    expect(repo.applyCalls, 0);
    expect(find.text(_apply), findsOneWidget);
  });

  testWidgets('авто режим: ариза → дарҳол панел', (tester) async {
    final repo = _FakeRepo(applyResult: 'approved');
    await _pump(tester, repo);
    await _applyAndConfirm(tester);

    expect(find.text(_panel), findsOneWidget);
    expect(find.text(_apply), findsNothing);
    expect(find.text('courier_apply_approved'), findsOneWidget);
  });

  testWidgets('applied ҳолатида очилди — фақат кутиш ёзуви', (tester) async {
    await _pump(tester, _FakeRepo(status: 'applied'));
    expect(find.text(_pending), findsOneWidget);
    expect(find.text(_panel), findsNothing);
    expect(find.text(_apply), findsNothing);
  });

  testWidgets('админ қўшган (approved) — панел, РОЛСИЗ ҳам', (tester) async {
    await _pump(tester, _FakeRepo(status: 'approved'));
    expect(find.text(_panel), findsOneWidget);
    expect(find.text(_apply), findsNothing);
    expect(find.text(_suspended), findsNothing);
  });

  testWidgets('эски trial курьер — панел (орқага мослик)', (tester) async {
    await _pump(tester, _FakeRepo(status: 'trial'));
    expect(find.text(_panel), findsOneWidget);
  });

  testWidgets('suspended — панел (қўлдаги иш, D-15.4) + огоҳлантириш',
      (tester) async {
    await _pump(tester, _FakeRepo(status: 'suspended'));
    expect(find.text(_panel), findsOneWidget);
    expect(find.text(_suspended), findsOneWidget);
    expect(find.text(_apply), findsNothing);
  });

  testWidgets('эски PIN роли + not_registered — панел аввалгидек, ариза йўқ',
      (tester) async {
    await _pump(tester, _FakeRepo(), legacy: true);
    expect(find.text(_panel), findsOneWidget);
    expect(find.text(_apply), findsNothing);
  });

  testWidgets('ҳолатни ўқиб бўлмади — ариза таклиф ҚИЛИНМАЙДИ', (tester) async {
    final repo = _FakeRepo()..fetchError = Exception('offline');
    await _pump(tester, repo);
    expect(find.text(_apply), findsNothing);
    expect(find.text(_panel), findsNothing);
  });

  testWidgets('сервер рад этди (failed-precondition) — тушунарли хабар',
      (tester) async {
    final repo = _FakeRepo()
      ..applyError = FirebaseFunctionsException(
        code: 'failed-precondition',
        message: '«suspended» holatidan boshlab bo\'lmaydi',
      );
    await _pump(tester, repo);
    // Сервер бошқача деди — экран ҳолатни қайта ўқийди.
    repo.status = 'suspended';
    await _applyAndConfirm(tester);

    expect(find.text('courier_apply_blocked'), findsOneWidget);
    expect(find.textContaining('holatidan'), findsNothing,
        reason: 'ички хато матни фойдаланувчига чиқмайди');
    expect(find.text(_suspended), findsOneWidget);
  });

  testWidgets('тармоқ хатоси — «қайта уриниб кўринг»', (tester) async {
    final repo = _FakeRepo()..applyError = Exception('timeout');
    await _pump(tester, repo);
    await _applyAndConfirm(tester);

    expect(find.text('courier_apply_failed'), findsOneWidget);
    expect(find.text(_apply), findsOneWidget, reason: 'қайта уриниш мумкин');
  });
}
