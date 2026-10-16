// Mijoz tasdig'i: karta, home banneri, ekran, kontroller (soxta servis bilan).
//
// Lokalizatsiya delegati ataylab yo'q — `context.tr` kalitning o'zini qaytaradi
// (test/features/carpet_wash/carpet_wash_courier_screen_test.dart kabi).
//
//   flutter test test/features/customer_confirm/customer_confirm_ui_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/features/customer_confirm/customer_confirm_controller.dart';
import 'package:ava_gurlan/features/customer_confirm/screens/customer_confirm_screen.dart';
import 'package:ava_gurlan/features/customer_confirm/widgets/customer_confirm_banner.dart';
import 'package:ava_gurlan/features/customer_confirm/widgets/customer_confirm_card.dart';
import 'package:ava_gurlan/models/customer_confirm.dart';
import 'package:ava_gurlan/services/customer_confirm_service.dart';

class _FakeService implements CustomerConfirmService {
  _FakeService(this.lists);

  /// Navbatdagi `listPending` javoblari (ro'yxat yoki xato); oxirgisi takrorlanadi.
  final List<Object> lists;
  int listCalls = 0;
  final List<String> confirms = [];
  Object? confirmError;

  @override
  Future<List<CustomerConfirmation>> listPending() async {
    final r = lists[listCalls < lists.length ? listCalls : lists.length - 1];
    listCalls++;
    if (r is List<CustomerConfirmation>) return r;
    throw r;
  }

  @override
  Future<CustomerConfirmResult> confirm({
    required String module,
    required String id,
    required String step,
  }) async {
    confirms.add('$module/$id/$step');
    final e = confirmError;
    if (e != null) throw e;
    return const CustomerConfirmResult();
  }
}

CustomerConfirmation _c(String module, String id, String step,
        {String title = '', CustomerConfirmDetails? details}) =>
    CustomerConfirmation(
        module: module, id: id, step: step, title: title, details: details);

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  group('CustomerConfirmCard', () {
    for (final (step, key) in [
      (CustomerConfirmStep.handoverPickup, 'customer_confirm_btn_handover'),
      (CustomerConfirmStep.handoverReturn, 'customer_confirm_btn_received'),
      (CustomerConfirmStep.received, 'customer_confirm_btn_received'),
      (CustomerConfirmStep.finalize, 'customer_confirm_btn_confirm'),
    ]) {
      testWidgets('qadam $step — tugma $key', (tester) async {
        var taps = 0;
        await tester.pumpWidget(_app(CustomerConfirmCard(
          item: _c('carpet', 'a', step),
          busy: false,
          onConfirm: () => taps++,
        )));
        expect(find.text(key), findsOneWidget);
        await tester.tap(find.text(key));
        expect(taps, 1);
      });
    }

    testWidgets('sarlavha bo\'sh — modul nomi; summary bo\'sh — qadam izohi',
        (tester) async {
      await tester.pumpWidget(_app(CustomerConfirmCard(
        item: _c('restaurant', 'a', CustomerConfirmStep.received),
        busy: false,
        onConfirm: () {},
      )));
      expect(find.text('customer_confirm_module_restaurant'), findsOneWidget);
      expect(find.text('customer_confirm_hint_received'), findsOneWidget);
    });

    testWidgets('server sarlavhasi bor — o\'sha ko\'rsatiladi', (tester) async {
      await tester.pumpWidget(_app(CustomerConfirmCard(
        item: _c('restaurant', 'a', CustomerConfirmStep.received, title: 'Osh markazi'),
        busy: false,
        onConfirm: () {},
      )));
      expect(find.text('Osh markazi'), findsOneWidget);
      expect(find.text('customer_confirm_module_restaurant'), findsNothing);
    });

    testWidgets('yig\'ish: kuryer kiritgan miqdor va summa ko\'rsatiladi', (tester) async {
      await tester.pumpWidget(_app(CustomerConfirmCard(
        item: _c('collection', 't1', CustomerConfirmStep.finalize,
            details: const CustomerConfirmDetails(
              qty: 12.5,
              unit: 'litr',
              amount: 87500,
              productLabel: 'Sut',
            )),
        busy: false,
        onConfirm: () {},
      )));
      expect(find.text('Sut'), findsOneWidget);
      // Lokalizatsiyasiz kalit qaytadi — {qty}/{unit} almashmaydi, lekin
      // butun satr kalitdan iborat; raqamlarni alohida tekshiramiz.
      expect(find.textContaining('customer_confirm_details_qty'), findsOneWidget);
      expect(find.textContaining('customer_confirm_details_amount'), findsOneWidget);
    });

    testWidgets('band holatda tugma bosilmaydi', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_app(CustomerConfirmCard(
        item: _c('carpet', 'a', CustomerConfirmStep.handoverPickup),
        busy: true,
        onConfirm: () => taps++,
      )));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      expect(taps, 0);
    });

    test('miqdor matni: butun va kasr', () {
      expect(customerConfirmQtyText(12), '12');
      expect(customerConfirmQtyText(12.0), '12');
      expect(customerConfirmQtyText(12.5), '12.5');
      expect(customerConfirmQtyText(0.25), '0.25');
    });
  });

  group('CustomerConfirmController', () {
    test('load: ro\'yxat olinadi; xatoda eski ro\'yxat saqlanadi', () async {
      final svc = _FakeService([
        [_c('carpet', 'a', 'handover_pickup')],
        Exception('network'),
      ]);
      final ctrl = CustomerConfirmController(service: svc);
      await ctrl.load();
      expect(ctrl.items, hasLength(1));
      expect(ctrl.loaded, isTrue);
      await ctrl.load();
      expect(ctrl.items, hasLength(1), reason: 'xato ro\'yxatni o\'chirmasin');
      expect(ctrl.loadError, isNotNull);
      ctrl.dispose();
    });

    test('confirm muvaffaqiyat: serverga ketadi, ro\'yxat yangilanadi, null qaytadi', () async {
      final svc = _FakeService([
        [_c('carpet', 'a', 'handover_pickup')],
        <CustomerConfirmation>[],
      ]);
      final ctrl = CustomerConfirmController(service: svc);
      await ctrl.load();
      final err = await ctrl.confirm(ctrl.items.single);
      expect(err, isNull);
      expect(svc.confirms, ['carpet/a/handover_pickup']);
      expect(ctrl.items, isEmpty);
      expect(svc.listCalls, 2);
      ctrl.dispose();
    });

    test('confirm xato: reason → matn kaliti; NOT_AWAITING da ro\'yxat yangilanadi', () async {
      final item = _c('carpet', 'a', 'handover_pickup');
      final svc = _FakeService([
        [item],
        <CustomerConfirmation>[],
      ])
        ..confirmError =
            const CustomerConfirmException('failed-precondition', 'NOT_AWAITING');
      final ctrl = CustomerConfirmController(service: svc);
      await ctrl.load();
      final err = await ctrl.confirm(item);
      expect(err, 'customer_confirm_err_not_awaiting');
      expect(svc.listCalls, 2, reason: 'ro\'yxat qayta olinishi kerak');
      expect(ctrl.items, isEmpty);
      expect(ctrl.isBusy(item), isFalse);
      ctrl.dispose();
    });

    test('noma\'lum xato — umumiy matn, ro\'yxat o\'zgarmaydi', () async {
      final item = _c('carpet', 'a', 'handover_pickup');
      final svc = _FakeService([
        [item],
      ])
        ..confirmError = Exception('boom');
      final ctrl = CustomerConfirmController(service: svc);
      await ctrl.load();
      final err = await ctrl.confirm(item);
      expect(err, 'customer_confirm_err_generic');
      expect(ctrl.items, hasLength(1));
      expect(svc.listCalls, 1);
      ctrl.dispose();
    });

    test('loadIfStale: yaqinda yuklangan bo\'lsa qayta chaqirmaydi', () async {
      final svc = _FakeService([
        <CustomerConfirmation>[],
      ]);
      final ctrl = CustomerConfirmController(service: svc);
      await ctrl.load();
      await ctrl.loadIfStale();
      expect(svc.listCalls, 1);
      await ctrl.loadIfStale(minAge: Duration.zero);
      expect(svc.listCalls, 2);
      ctrl.dispose();
    });
  });

  group('CustomerConfirmBanner', () {
    testWidgets('ro\'yxat bo\'sh — hech narsa ko\'rinmaydi', (tester) async {
      final svc = _FakeService([<CustomerConfirmation>[]]);
      await tester.pumpWidget(_app(CustomerConfirmBanner(service: svc)));
      await tester.pumpAndSettle();
      expect(find.text('customer_confirm_title'), findsNothing);
      expect(find.byType(CustomerConfirmCard), findsNothing);
    });

    testWidgets('eski server / tarmoq xatosi — bosh sahifada xato ko\'rsatilmaydi',
        (tester) async {
      final svc = _FakeService([
        const CustomerConfirmException('not-found', ''),
      ]);
      await tester.pumpWidget(_app(CustomerConfirmBanner(service: svc)));
      await tester.pumpAndSettle();
      expect(find.text('customer_confirm_title'), findsNothing);
      expect(find.textContaining('customer_confirm_err'), findsNothing);
    });

    testWidgets('element bor — sarlavha va tugma; bosilsa serverga ketadi va yo\'qoladi',
        (tester) async {
      final svc = _FakeService([
        [_c('carpet', 'a', CustomerConfirmStep.handoverPickup)],
        <CustomerConfirmation>[],
      ]);
      await tester.pumpWidget(_app(CustomerConfirmBanner(service: svc)));
      await tester.pumpAndSettle();
      expect(find.text('customer_confirm_title'), findsOneWidget);
      expect(find.text('customer_confirm_btn_handover'), findsOneWidget);

      await tester.tap(find.text('customer_confirm_btn_handover'));
      await tester.pumpAndSettle();
      expect(svc.confirms, ['carpet/a/handover_pickup']);
      expect(find.byType(CustomerConfirmCard), findsNothing);
      expect(find.text('customer_confirm_done'), findsOneWidget); // snackbar
    });

    testWidgets('xato — do\'stona matn snackbar\'da, ichki kod ko\'rinmaydi', (tester) async {
      final item = _c('carpet', 'a', CustomerConfirmStep.received);
      final svc = _FakeService([
        [item],
        [item],
      ])
        ..confirmError =
            const CustomerConfirmException('failed-precondition', 'STATE_CHANGED');
      await tester.pumpWidget(_app(CustomerConfirmBanner(service: svc)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('customer_confirm_btn_received'));
      await tester.pumpAndSettle();
      expect(find.text('customer_confirm_err_state_changed'), findsOneWidget);
      expect(find.textContaining('STATE_CHANGED'), findsNothing);
    });

    testWidgets('maxInline dan ortig\'i — «Yana N ta» tugmasi', (tester) async {
      final svc = _FakeService([
        [
          _c('carpet', 'a', 'handover_pickup'),
          _c('carpet', 'b', 'handover_pickup'),
          _c('agro', 'c', 'handover_pickup'),
        ],
      ]);
      await tester.pumpWidget(_app(CustomerConfirmBanner(service: svc)));
      await tester.pumpAndSettle();
      expect(find.byType(CustomerConfirmCard), findsNWidgets(2));
      expect(find.textContaining('customer_confirm_more'), findsOneWidget);
    });

    testWidgets('FCM signali — ro\'yxat qayta olinadi', (tester) async {
      final svc = _FakeService([
        <CustomerConfirmation>[],
        [_c('carpet', 'a', CustomerConfirmStep.handoverPickup)],
      ]);
      await tester.pumpWidget(_app(CustomerConfirmBanner(service: svc)));
      await tester.pumpAndSettle();
      expect(find.byType(CustomerConfirmCard), findsNothing);

      CustomerConfirmSignal.bump();
      await tester.pumpAndSettle();
      expect(svc.listCalls, 2);
      expect(find.byType(CustomerConfirmCard), findsOneWidget);
    });
  });

  group('CustomerConfirmScreen', () {
    testWidgets('bo\'sh — «hozir yo\'q» matni', (tester) async {
      final svc = _FakeService([<CustomerConfirmation>[]]);
      await tester.pumpWidget(MaterialApp(home: CustomerConfirmScreen(service: svc)));
      await tester.pumpAndSettle();
      expect(find.text('customer_confirm_empty'), findsOneWidget);
    });

    testWidgets('xato «bo\'sh» deb yashirilmaydi, qayta urinish ishlaydi', (tester) async {
      final svc = _FakeService([
        Exception('network'),
        [_c('collection', 't', CustomerConfirmStep.finalize)],
      ]);
      await tester.pumpWidget(MaterialApp(home: CustomerConfirmScreen(service: svc)));
      await tester.pumpAndSettle();
      expect(find.text('customer_confirm_err_load'), findsOneWidget);
      expect(find.text('customer_confirm_empty'), findsNothing);

      await tester.tap(find.text('customer_confirm_refresh'));
      await tester.pumpAndSettle();
      expect(find.text('customer_confirm_btn_confirm'), findsOneWidget);
    });

    testWidgets('pull-to-refresh ro\'yxatni qayta oladi', (tester) async {
      final svc = _FakeService([
        <CustomerConfirmation>[],
        [_c('agro', 'a', CustomerConfirmStep.handoverPickup)],
      ]);
      await tester.pumpWidget(MaterialApp(home: CustomerConfirmScreen(service: svc)));
      await tester.pumpAndSettle();
      await tester.fling(find.text('customer_confirm_empty'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(svc.listCalls, 2);
      expect(find.text('customer_confirm_btn_handover'), findsOneWidget);
    });
  });
}
