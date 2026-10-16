// Admin "Mijoz tasdig'i": bosqich (OFF/INTERNAL/PUBLIC) va sinovchilar.
//
//   flutter test test/features/admin_web/customer_confirm_admin_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/features/admin_web/screens/customer_confirm_admin_screen.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_callable.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_customer_confirm_service.dart';
import 'package:ava_gurlan/features/admin_web/utils/customer_confirm_admin.dart';

class _FakeCallable implements AdminCallable {
  _FakeCallable(this.handler);

  final Future<Map<String, dynamic>> Function(String name, Map<String, dynamic> payload) handler;
  final calls = <(String, Map<String, dynamic>)>[];

  @override
  Future<Map<String, dynamic>> call(String name, Map<String, dynamic> payload) {
    calls.add((name, payload));
    return handler(name, payload);
  }
}

Map<String, dynamic> _state({String restaurant = 'off', int testers = 2}) => {
      'ok': true,
      'modules': {
        'restaurant': {'stage': restaurant},
        'carpet': {'stage': 'internal'},
        'agro': {'stage': 'public'},
        'collection': {'stage': 'off'},
      },
      'testerCount': testers,
    };

Future<void> _pump(WidgetTester tester, _FakeCallable fake) async {
  tester.view.physicalSize = const Size(1200, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: CustomerConfirmAdminBody(svc: AdminCustomerConfirmService(callable: fake)),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _confirmReason(WidgetTester tester, String reason) async {
  await tester.enterText(find.byType(TextField).last, reason);
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Тасдиқлаш'));
  await tester.pumpAndSettle();
}

void main() {
  group('CustomerConfirmState.fromMap', () {
    test('server javobi', () {
      final s = CustomerConfirmState.fromMap(_state());
      expect(s.stages['restaurant'], 'off');
      expect(s.stages['carpet'], 'internal');
      expect(s.stages['agro'], 'public');
      expect(s.testerCount, 2);
    });
    test('bo\'sh / noto\'g\'ri / noma\'lum bosqich — null, yiqilmaydi', () {
      final s = CustomerConfirmState.fromMap({
        'modules': {
          'restaurant': 'x',
          'carpet': {'stage': 'PILOT'},
          'agro': {'stage': ' Public '},
        },
        'testerCount': 'x',
      });
      expect(s.stages['restaurant'], isNull);
      expect(s.stages['carpet'], isNull);
      expect(s.stages['agro'], 'public');
      expect(s.stages['collection'], isNull);
      expect(s.testerCount, isNull);
      expect(CustomerConfirmState.fromMap({'modules': 5}).stages.keys.toSet(),
          kCustomerConfirmModules.keys.toSet());
    });
    test('natija matni', () {
      expect(
          CustomerConfirmSetResult.fromMap({'ok': true, 'unchanged': true, 'stage': 'off', 'testerCount': 1})
              .describe(),
          'Ўзгариш йўқ · босқич: OFF · синовчилар: 1');
      expect(CustomerConfirmSetResult.fromMap({'ok': true, 'stage': 'public'}).describe(),
          'Сақланди · босқич: PUBLIC');
    });
  });

  group('AdminCustomerConfirmService', () {
    test('payload: faqat berilgan maydonlar, reason trim', () async {
      final fake = _FakeCallable((n, p) async => {'ok': true});
      final svc = AdminCustomerConfirmService(callable: fake);
      await svc.set(module: 'carpet', stage: 'public', reason: '  ega qarori ');
      await svc.set(module: 'agro', addTesterIds: ['901112233'], reason: 'sinov');
      await svc.set(module: 'agro', removeTesterIds: ['998901112233'], addTesterIds: [], reason: 'olish');
      expect(fake.calls[0].$2, {'module': 'carpet', 'stage': 'public', 'reason': 'ega qarori'});
      expect(fake.calls[1].$2, {'module': 'agro', 'addTesterIds': ['901112233'], 'reason': 'sinov'});
      expect(fake.calls[2].$2, {'module': 'agro', 'removeTesterIds': ['998901112233'], 'reason': 'olish'});
      expect(fake.calls.every((c) => c.$1 == 'adminSetCustomerConfirmation'), isTrue);
    });
  });

  group('CustomerConfirmAdminBody', () {
    testWidgets('yuklaydi: 4 qator, ogohlantirish, sinovchilar soni', (tester) async {
      final fake = _FakeCallable((n, p) async => _state());
      await _pump(tester, fake);
      expect(fake.calls.single.$1, 'adminGetCustomerConfirmation');
      expect(fake.calls.single.$2, <String, dynamic>{});
      for (final label in kCustomerConfirmModules.values) {
        expect(find.text(label), findsWidgets);
      }
      expect(find.byType(DropdownButton<String>), findsNWidgets(5)); // 4 modul + sinovchi moduli
      expect(find.textContaining('ЯНГИ версиясидан'), findsOneWidget);
      expect(find.textContaining('Синовчилар сони (серверда): 2'), findsOneWidget);
      // O'zgarish yo'q — "Saqlash" o'chiq
      final save = tester.widget<FilledButton>(find.byKey(const ValueKey('save_restaurant')));
      expect(save.onPressed, isNull);
    });

    testWidgets('bosqich: tanlash -> sabab dialogi -> payload -> qayta yuklash', (tester) async {
      var stage = 'off';
      final fake = _FakeCallable((n, p) async {
        if (n == 'adminSetCustomerConfirmation') {
          stage = p['stage'] as String;
          return {'ok': true, 'unchanged': false, 'stage': stage, 'testerCount': 2};
        }
        return _state(restaurant: stage);
      });
      await _pump(tester, fake);

      await tester.tap(find.byKey(const ValueKey('stage_restaurant')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kCustomerConfirmStageLabels['public']!).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save_restaurant')));
      await tester.pumpAndSettle();
      // PUBLIC dialogida ogohlantirish matni
      expect(find.textContaining('ЯНГИ версиясидан'), findsWidgets);
      await _confirmReason(tester, 'ega qarori');

      final set = fake.calls.firstWhere((c) => c.$1 == 'adminSetCustomerConfirmation');
      expect(set.$2, {'module': 'restaurant', 'stage': 'public', 'reason': 'ega qarori'});
      expect(fake.calls.last.$1, 'adminGetCustomerConfirmation', reason: 'saqlangach qayta o\'qiladi');
      // restoran + agro (ikkalasi ham PUBLIC)
      expect(find.textContaining('серверда: PUBLIC'), findsNWidgets(2));
    });

    testWidgets('sabab dialogi bekor — serverga hech narsa ketmaydi', (tester) async {
      final fake = _FakeCallable((n, p) async => _state());
      await _pump(tester, fake);
      await tester.tap(find.byKey(const ValueKey('stage_restaurant')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kCustomerConfirmStageLabels['internal']!).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save_restaurant')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Бекор'));
      await tester.pumpAndSettle();
      expect(fake.calls.where((c) => c.$1 == 'adminSetCustomerConfirmation'), isEmpty);
    });

    testWidgets('sinovchi qo\'shish: telefon normallashadi, tanlangan modulga ketadi', (tester) async {
      final fake = _FakeCallable((n, p) async {
        if (n == 'adminSetCustomerConfirmation') {
          return {'ok': true, 'unchanged': false, 'stage': 'off', 'testerCount': 3};
        }
        return _state();
      });
      await _pump(tester, fake);
      await tester.enterText(find.byType(TextField), '+998 (90) 111-22-33');
      await tester.tap(find.byKey(const ValueKey('tester_add')));
      await tester.pumpAndSettle();
      await _confirmReason(tester, 'sinov');
      final set = fake.calls.firstWhere((c) => c.$1 == 'adminSetCustomerConfirmation');
      expect(set.$2, {
        'module': 'restaurant',
        'addTesterIds': ['998901112233'],
        'reason': 'sinov',
      });
    });

    testWidgets('sinovchi olish: removeTesterIds; noto\'g\'ri telefon serverga ketmaydi', (tester) async {
      final fake = _FakeCallable((n, p) async {
        if (n == 'adminSetCustomerConfirmation') {
          return {'ok': true, 'unchanged': true, 'stage': 'off', 'testerCount': 2};
        }
        return _state();
      });
      await _pump(tester, fake);

      await tester.enterText(find.byType(TextField), '12345');
      await tester.tap(find.byKey(const ValueKey('tester_remove')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Телефон: 9 рақам'), findsOneWidget);
      expect(fake.calls.where((c) => c.$1 == 'adminSetCustomerConfirmation'), isEmpty);

      await tester.enterText(find.byType(TextField), '901112233');
      await tester.tap(find.byKey(const ValueKey('tester_remove')));
      await tester.pumpAndSettle();
      await _confirmReason(tester, 'olish');
      final set = fake.calls.firstWhere((c) => c.$1 == 'adminSetCustomerConfirmation');
      expect(set.$2, {'module': 'restaurant', 'removeTesterIds': ['901112233'], 'reason': 'olish'});
    });

    testWidgets('yuklash xatosi — matn va "Qayta"', (tester) async {
      final fake = _FakeCallable((n, p) async =>
          throw const AdminCallableException('permission-denied', '', 'Admin role required'));
      await _pump(tester, fake);
      expect(find.textContaining('Рухсат йўқ'), findsOneWidget);
      expect(find.text('Қайта'), findsOneWidget);
    });

    testWidgets('saqlash xatosi — snackbar, ekran yiqilmaydi', (tester) async {
      final fake = _FakeCallable((n, p) async {
        if (n == 'adminSetCustomerConfirmation') {
          throw const AdminCallableException('failed-precondition', 'stage_invalid', 'x');
        }
        return _state();
      });
      await _pump(tester, fake);
      await tester.tap(find.byKey(const ValueKey('stage_carpet')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kCustomerConfirmStageLabels['off']!).last);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('save_carpet')));
      await tester.pumpAndSettle();
      await _confirmReason(tester, 'sabab');
      expect(find.textContaining('Босқич номаълум'), findsOneWidget);
    });
  });
}
