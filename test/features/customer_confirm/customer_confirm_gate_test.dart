// Mijoz tasdig'i: xarajat nazorati — `module_config/customer_confirm` gate'i.
// Hujjat yoq / enabled=false / oqib bolmadi => getCustomerPendingConfirmations
// UMUMAN chaqirilmaydi; faqat enabled=true => chaqiriladi.
//
//   flutter test test/features/customer_confirm/customer_confirm_gate_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/features/customer_confirm/customer_confirm_controller.dart';
import 'package:ava_gurlan/features/customer_confirm/customer_confirm_gate.dart';
import 'package:ava_gurlan/features/customer_confirm/screens/customer_confirm_screen.dart';
import 'package:ava_gurlan/features/customer_confirm/widgets/customer_confirm_banner.dart';
import 'package:ava_gurlan/models/customer_confirm.dart';
import 'package:ava_gurlan/services/customer_confirm_service.dart';

class _CountingService implements CustomerConfirmService {
  _CountingService(this.items);
  final List<CustomerConfirmation> items;
  int listCalls = 0;

  @override
  Future<List<CustomerConfirmation>> listPending() async {
    listCalls++;
    return items;
  }

  @override
  Future<CustomerConfirmResult> confirm({
    required String module,
    required String id,
    required String step,
  }) async =>
      const CustomerConfirmResult();
}

const _item = CustomerConfirmation(
  module: 'carpet',
  id: 'a',
  step: CustomerConfirmStep.handoverPickup,
  title: '',
);

/// Hujjat holatini taqlid qiladi: map => hujjat bor; null => yoq; Exception => oqish xatosi.
class _Doc {
  _Doc(this.value);
  Object? value;
  int reads = 0;

  Future<bool> read() async {
    reads++;
    final v = value;
    if (v is Exception) throw v;
    return CustomerConfirmGate.parseEnabled(v as Map<String, dynamic>?);
  }
}

Widget _app(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  group('CustomerConfirmGate.parseEnabled', () {
    test('faqat qat\'iy enabled == true', () {
      expect(CustomerConfirmGate.parseEnabled(null), isFalse);
      expect(CustomerConfirmGate.parseEnabled(const {}), isFalse);
      expect(CustomerConfirmGate.parseEnabled(const {'enabled': false}), isFalse);
      expect(CustomerConfirmGate.parseEnabled(const {'enabled': 'true'}), isFalse);
      expect(CustomerConfirmGate.parseEnabled(const {'enabled': 1}), isFalse);
      expect(CustomerConfirmGate.parseEnabled(const {'enabled': true}), isTrue);
    });
  });

  group('CustomerConfirmGate.isEnabled', () {
    test('true / false / yoq / xato', () async {
      for (final (value, expected) in <(Object?, bool)>[
        (<String, dynamic>{'enabled': true}, true),
        (<String, dynamic>{'enabled': false}, false),
        (null, false),
        (Exception('permission-denied'), false),
      ]) {
        final doc = _Doc(value);
        expect(await CustomerConfirmGate(reader: doc.read).isEnabled(), expected,
            reason: '$value');
      }
    });

    test('muvaffaqiyatli oqish ttl davomida keshlanadi, force chetlab oladi', () async {
      var now = DateTime(2026, 10, 16, 12);
      final doc = _Doc(<String, dynamic>{'enabled': true});
      final gate = CustomerConfirmGate(
        reader: doc.read,
        ttl: const Duration(minutes: 10),
        now: () => now,
      );
      expect(await gate.isEnabled(), isTrue);
      expect(await gate.isEnabled(), isTrue);
      expect(doc.reads, 1);

      doc.value = <String, dynamic>{'enabled': false};
      expect(await gate.isEnabled(), isTrue); // kesh
      expect(await gate.isEnabled(force: true), isFalse);
      expect(doc.reads, 2);

      now = now.add(const Duration(minutes: 11));
      doc.value = <String, dynamic>{'enabled': true};
      expect(await gate.isEnabled(), isTrue); // ttl otdi
      expect(doc.reads, 3);
    });

    test('oqish xatosi keshlanmaydi: keyingi urinishda qayta oqiladi', () async {
      final doc = _Doc(Exception('offline'));
      final gate = CustomerConfirmGate(reader: doc.read);
      expect(await gate.isEnabled(), isFalse);
      doc.value = <String, dynamic>{'enabled': true};
      expect(await gate.isEnabled(), isTrue);
      expect(doc.reads, 2);
    });

    test('parallel chaqiruvlar bitta oqishga birlashadi', () async {
      final doc = _Doc(<String, dynamic>{'enabled': true});
      final gate = CustomerConfirmGate(reader: doc.read);
      final r = await Future.wait([gate.isEnabled(), gate.isEnabled(), gate.isEnabled()]);
      expect(r, [true, true, true]);
      expect(doc.reads, 1);
    });
  });

  group('CustomerConfirmController + gate', () {
    for (final (name, value, calls) in <(String, Object?, int)>[
      ('enabled=true', <String, dynamic>{'enabled': true}, 1),
      ('enabled=false', <String, dynamic>{'enabled': false}, 0),
      ('hujjat yoq', null, 0),
      ('oqish xatosi', Exception('unavailable'), 0),
    ]) {
      test('$name — callable $calls marta', () async {
        final svc = _CountingService([_item]);
        final ctrl = CustomerConfirmController(
          service: svc,
          gate: CustomerConfirmGate(reader: _Doc(value).read),
        );
        await ctrl.load();
        expect(svc.listCalls, calls);
        expect(ctrl.items.length, calls);
        expect(ctrl.loadError, isNull);
        ctrl.dispose();
      });
    }

    test('gate berilmasa — ekran kabi har doim chaqiradi', () async {
      final svc = _CountingService([_item]);
      final ctrl = CustomerConfirmController(service: svc);
      await ctrl.load();
      expect(svc.listCalls, 1);
      ctrl.dispose();
    });

    test('ochiq xususiyat ochirilsa — royxat tozalanadi', () async {
      final doc = _Doc(<String, dynamic>{'enabled': true});
      final svc = _CountingService([_item]);
      final ctrl = CustomerConfirmController(
        service: svc,
        gate: CustomerConfirmGate(reader: doc.read),
      );
      await ctrl.load();
      expect(ctrl.items, isNotEmpty);
      doc.value = <String, dynamic>{'enabled': false};
      await ctrl.load(forceGate: true);
      expect(ctrl.items, isEmpty);
      expect(svc.listCalls, 1);
      ctrl.dispose();
    });
  });

  group('CustomerConfirmBanner + gate', () {
    testWidgets('ochiq — blok korinadi, callable 1 marta', (tester) async {
      final svc = _CountingService([_item]);
      await tester.pumpWidget(_app(CustomerConfirmBanner(
        service: svc,
        gate: CustomerConfirmGate(reader: _Doc(<String, dynamic>{'enabled': true}).read),
      )));
      await tester.pumpAndSettle();
      expect(svc.listCalls, 1);
      expect(find.text('customer_confirm_title'), findsOneWidget);
    });

    for (final (name, value) in <(String, Object?)>[
      ('enabled=false', <String, dynamic>{'enabled': false}),
      ('hujjat yoq', null),
      ('oqish xatosi', Exception('unavailable')),
    ]) {
      testWidgets('$name — callable chaqirilmaydi, blok korinmaydi', (tester) async {
        final svc = _CountingService([_item]);
        await tester.pumpWidget(_app(CustomerConfirmBanner(
          service: svc,
          gate: CustomerConfirmGate(reader: _Doc(value).read),
        )));
        await tester.pumpAndSettle();
        expect(svc.listCalls, 0);
        expect(find.text('customer_confirm_title'), findsNothing);
      });
    }

    testWidgets('push signali gate keshini chetlab otadi: ochilgan xususiyat korinadi',
        (tester) async {
      final doc = _Doc(<String, dynamic>{'enabled': false});
      final svc = _CountingService([_item]);
      await tester.pumpWidget(_app(CustomerConfirmBanner(
        service: svc,
        gate: CustomerConfirmGate(reader: doc.read),
      )));
      await tester.pumpAndSettle();
      expect(svc.listCalls, 0);

      doc.value = <String, dynamic>{'enabled': true};
      CustomerConfirmSignal.bump();
      await tester.pumpAndSettle();
      expect(svc.listCalls, 1);
      expect(find.text('customer_confirm_title'), findsOneWidget);
    });
  });

  group('CustomerConfirmScreen (push bosilganda)', () {
    testWidgets('gate yoq — xususiyat ochiq/yopiqligidan qat\'i nazar royxat olinadi',
        (tester) async {
      final svc = _CountingService([_item]);
      await tester.pumpWidget(MaterialApp(home: CustomerConfirmScreen(service: svc)));
      await tester.pumpAndSettle();
      expect(svc.listCalls, 1);
      expect(find.text('customer_confirm_btn_handover'), findsOneWidget);
    });
  });
}