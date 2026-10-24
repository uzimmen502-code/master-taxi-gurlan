// Yig'ish (qabul) vazifasi: kuryer "Yig'ishni yakunlash" bosganda server
// awaitingCustomer qaytarsa — mijoz tasdig'i kutiladi (D2/D7). Eski serverda
// avvalgidek "qabul qilindi" ko'rinishi.
//
//   flutter test test/features/courier/courier_collection_awaiting_test.dart

import 'package:ava_gurlan/features/courier/screens/courier_collection_detail_screen.dart';
import 'package:ava_gurlan/models/collection_task.dart';
import 'package:ava_gurlan/repositories/collection_tasks_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _courier = '998901110001';

const _item = CollectionItem(
  code: 'milk',
  label: 'Sut',
  unit: 'litr',
  qty: 10,
  unitPrice: 5000,
  lineTotal: 50000,
);

CollectionTask _task({String status = 'collecting'}) => CollectionTask(
      id: 't1',
      submissionId: 's1',
      customerPhone: '', // balans so'rovi (Firebase) o'tkazib yuboriladi
      customerUid: '',
      customerName: 'Mijoz',
      pickupAddress: 'Navoiy 7',
      items: const [_item],
      totalValue: 50000,
      courierId: _courier,
      status: status,
      arrivedAt: DateTime(2026, 10, 16),
    );

class _FakeRepo implements CollectionTasksRepository {
  _FakeRepo(this.results);

  /// `getById` navbatdagi javoblari; oxirgisi takrorlanadi.
  final List<CollectionTask?> results;
  int calls = 0;

  @override
  Future<CollectionTask?> getById(String id) async {
    final r = results[calls < results.length ? calls : results.length - 1];
    calls++;
    return r;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Finalize {
  _Finalize(this.response);

  final Map<String, dynamic> response;
  final calls = <List<Map<String, dynamic>>>[];

  Future<Map<String, dynamic>> call({
    required String courierPhone,
    required String taskId,
    required List<Map<String, dynamic>> items,
    required int cashGiven,
  }) async {
    calls.add(items);
    return response;
  }
}

Future<void> _open(
  WidgetTester tester, {
  required _Finalize finalize,
  required _FakeRepo repo,
}) async {
  tester.view.physicalSize = const Size(900, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'user_phone': _courier});
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
            builder: (_) => CourierCollectionDetailScreen(
              task: _task(),
              repository: repo,
              finalize: finalize.call,
            ),
          )),
          child: const Text('open'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  // Yig'ishni yakunlash → hisob-kitob varag'i → Tasdiqlash
  await tester.tap(find.text('crr_task_finalize_btn'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('confirm'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('awaitingCustomer: varaqda kutish, "qabul qilindi" YO\'Q; yopilgach tugma o\'chiq, raqamlar qulf',
      (tester) async {
    final finalize = _Finalize({'ok': true, 'awaitingCustomer': true, 'step': 'finalize'});
    final repo = _FakeRepo([_task()]);
    await _open(tester, finalize: finalize, repo: repo);

    expect(finalize.calls, hasLength(1));
    expect(finalize.calls.single.single['qty'], 10);
    // Varaqda ham, orqadagi ekranda ham (2 + 1) kutish ko'rinadi.
    expect(find.text('customer_confirm_waiting'), findsNWidgets(3));
    expect(find.textContaining('crr_task_received'), findsNothing);

    await tester.tap(find.text('ok'));
    await tester.pumpAndSettle();

    // Bottom bar: kutish bloki + o'chiq tugma; "Yakunlash" tugmasi YO'Q.
    expect(find.text('customer_confirm_waiting'), findsNWidgets(2));
    expect(find.text('crr_task_finalize_btn'), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse, reason: 'mijoz ko\'rayotganda raqam o\'zgarmaydi');

    // Yopilgach ekran 1 marta holatni tekshirdi (faol — qoladi).
    expect(repo.calls, 1);

    await tester.pumpWidget(const SizedBox()); // taymer to'xtasin
  });

  testWidgets('kutish: mijoz tasdiqlab vazifa yakunlansa (completed) ekran ro\'yxatga qaytadi',
      (tester) async {
    final finalize = _Finalize({'ok': true, 'awaitingCustomer': true});
    final repo = _FakeRepo([_task(), _task(status: 'completed')]);
    await _open(tester, finalize: finalize, repo: repo);
    await tester.tap(find.text('ok'));
    await tester.pumpAndSettle();
    expect(find.text('customer_confirm_waiting_hint'), findsOneWidget);
    expect(repo.calls, 1); // sheet yopilgach bir marta

    await tester.pump(const Duration(seconds: 9));
    await tester.pumpAndSettle();
    expect(repo.calls, 2);
    expect(find.text('open'), findsOneWidget, reason: 'ro\'yxatga qaytdi');
    expect(find.byType(CourierCollectionDetailScreen), findsNothing);
  });

  testWidgets('eski server (awaitingCustomer yo\'q): avvalgidek "Маҳсулот қабул қилинди"',
      (tester) async {
    final finalize = _Finalize({
      'ok': true,
      'V': 50000,
      'cashGiven': 0,
      'walletCredit': 50000,
      'newBalance': 50000,
    });
    final repo = _FakeRepo([_task()]);
    await _open(tester, finalize: finalize, repo: repo);

    expect(find.textContaining('crr_task_received'), findsOneWidget);
    expect(find.text('customer_confirm_waiting'), findsNothing);

    await tester.tap(find.text('courier_finalize'));
    await tester.pumpAndSettle();
    expect(find.byType(CourierCollectionDetailScreen), findsNothing);
    expect(repo.calls, 0, reason: 'kutish bo\'lmasa holat tekshirilmaydi');
  });
}
