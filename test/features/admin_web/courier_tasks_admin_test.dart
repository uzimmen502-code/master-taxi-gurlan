// Admin "Kuryer vazifalari": kuryer haqi foizi va qotib qolgan vazifalar.
//
//   flutter test test/features/admin_web/courier_tasks_admin_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ava_gurlan/features/admin_web/screens/courier_tasks_admin_screen.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_callable.dart';
import 'package:ava_gurlan/features/admin_web/services/admin_courier_tasks_service.dart';
import 'package:ava_gurlan/features/admin_web/utils/courier_tasks_admin.dart';

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

void main() {
  group('CourierPayoutSettings', () {
    test('null modullar = sozlanmagan, bps/100 foiz', () {
      final s = CourierPayoutSettings.fromMap({
        'ok': true,
        'version': 3,
        'modules': {
          'carpet': {'bps': 7000},
          'agro': null,
          'collection': {'bps': 6250},
        },
        'updatedAtMs': 1760000000000,
        'updatedBy': '998901112233',
      });
      expect(s.version, 3);
      expect(s.bps['carpet'], 7000);
      expect(s.bps['agro'], isNull);
      expect(s.percentText('carpet'), '70');
      expect(s.percentText('collection'), '62.5');
      expect(s.percentText('agro'), '');
    });
    test('bo\'sh/noto\'g\'ri javob — hammasi sozlanmagan', () {
      final s = CourierPayoutSettings.fromMap({'modules': 'x'});
      expect(s.version, 0);
      expect(s.bps.values.every((v) => v == null), isTrue);
      expect(s.bps.keys.toSet(), kCourierPayoutModules.keys.toSet());
    });
  });

  group('planPayoutPctChange', () {
    test('foiz -> bps; chegaralar 0 va 100 qabul', () {
      expect(planPayoutPctChange(currentBps: null, text: '70').bps, 7000);
      expect(planPayoutPctChange(currentBps: null, text: '62,5').bps, 6250);
      expect(planPayoutPctChange(currentBps: 5000, text: '0').bps, 0);
      expect(planPayoutPctChange(currentBps: 5000, text: '100').bps, 10000);
      expect(planPayoutPctChange(currentBps: 5000, text: '0').changed, isTrue);
    });
    test('100.01, manfiy, harf — xato', () {
      for (final t in ['100.01', '-1', 'abc', '101']) {
        final p = planPayoutPctChange(currentBps: null, text: t);
        expect(p.error, isNotNull, reason: t);
        expect(p.changed, isFalse, reason: t);
      }
    });
    test('bo\'sh = sozlanmaganga qaytarish (faqat qiymat bor bo\'lsa o\'zgarish)', () {
      final reset = planPayoutPctChange(currentBps: 7000, text: ' ');
      expect(reset.bps, isNull);
      expect(reset.changed, isTrue);
      expect(planPayoutPctChange(currentBps: null, text: '').changed, isFalse);
      expect(planPayoutPctChange(currentBps: null, text: 'sozlanmagan').changed, isFalse);
    });
    test('bir xil qiymat — o\'zgarish yo\'q', () {
      expect(planPayoutPctChange(currentBps: 7000, text: '70').changed, isFalse);
    });
  });

  group('StaleTasksResult', () {
    test('server javobi', () {
      final r = StaleTasksResult.fromMap({
        'ok': true,
        'hours': 3,
        'generatedAtMs': 1760000000000,
        'modules': {
          'carpet': {
            'items': [
              {'id': 'c1', 'status': 'pickup_in_delivery', 'updatedAtMs': 1, 'courierId': '99890', 'ageHours': 5.2},
              {'id': 'c2', 'status': 'accepted', 'courierId': '', 'ageHours': null},
            ],
            'total': 40,
            'scanned': 200,
            'truncated': true,
          },
        },
      });
      expect(r.hours, 3);
      expect(r.modules.keys.toList(), kStaleModuleLabels.keys.toList(), reason: 'barcha 6 modul, tartib bir xil');
      final c = r.modules['carpet']!;
      expect(c.items.length, 2);
      expect(c.total, 40);
      expect(c.truncated, isTrue);
      expect(c.items[0].ageHours, 5.2);
      expect(c.items[1].ageHours, isNull);
      expect(r.modules['agro']!.items, isEmpty);
      expect(r.totalAll, 40);
    });
    test('axlat kirish yiqitmaydi', () {
      final r = StaleTasksResult.fromMap({'modules': {'carpet': 5, 'agro': {'items': 'x'}}});
      expect(r.totalAll, 0);
    });
    test('soat tekshiruvi 1..168', () {
      expect(parseStaleHours('1'), 1);
      expect(parseStaleHours(' 168 '), 168);
      for (final t in ['0', '169', '-1', '', 'x', '1.5']) {
        expect(parseStaleHours(t), isNull, reason: t);
      }
    });
    test('yosh matni', () {
      expect(formatStaleAge(null), 'вақти номаълум');
      expect(formatStaleAge(3), '3 соат');
      expect(formatStaleAge(5.2), '5,2 соат');
      expect(formatStaleAge(47.9), '47,9 соат');
      expect(formatStaleAge(48), '2 кун');
      expect(formatStaleAge(75.5), '3 кун 3 соат');
    });
  });

  group('ekran (soxta callable)', () {
    testWidgets('qotib qolgan: yuklanadi, "ko\'proq bor" ko\'rinadi, soat noto\'g\'ri bo\'lsa chaqirilmaydi', (tester) async {
      final fake = _FakeCallable((name, p) async {
        if (name == 'adminListStaleTasks') {
          return {
            'ok': true,
            'hours': p['hours'],
            'generatedAtMs': 1760000000000,
            'modules': {
              'carpet': {
                'items': [
                  {'id': 'carpet-1', 'status': 'pickup_in_delivery', 'courierId': '998901112233', 'ageHours': 7.0},
                ],
                'total': 150,
                'scanned': 200,
                'truncated': true,
              },
            },
          };
        }
        return {};
      });
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StaleTasksTab(svc: AdminCourierTasksService(callable: fake))),
      ));
      await tester.pumpAndSettle();
      expect(fake.calls.single.$1, 'adminListStaleTasks');
      expect(fake.calls.single.$2, {'hours': 3});
      expect(find.textContaining('КЎПРОҚ БОР'), findsWidgets);
      expect(find.text('carpet-1'), findsOneWidget);
      expect(find.text('7 соат'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '999');
      await tester.tap(find.text('Янгилаш'));
      await tester.pumpAndSettle();
      expect(fake.calls.length, 1, reason: 'noto\'g\'ri soat serverga yuborilmaydi');
      expect(find.textContaining('оралиғида'), findsOneWidget);
    });

    testWidgets('xato: matn ko\'rsatiladi', (tester) async {
      final fake = _FakeCallable((name, p) async =>
          throw const AdminCallableException('permission-denied', '', 'Admin role required'));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: StaleTasksTab(svc: AdminCourierTasksService(callable: fake))),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Рухсат йўқ'), findsOneWidget);
    });

    testWidgets('kuryer haqi: getter callable, "sozlanmagan" va saqlash bps yuboradi', (tester) async {
      var saved = false;
      final fake = _FakeCallable((name, p) async {
        if (name == 'adminGetCourierTaskPayoutSettings') {
          return {
            'ok': true,
            'version': saved ? 2 : 1,
            'modules': {
              'carpet': {'bps': saved ? 7500 : 7000},
              'agro': null,
              'collection': null,
            },
          };
        }
        if (name == 'adminSetCourierTaskPayoutPct') {
          saved = true;
          return {'ok': true, 'version': 2, 'unchanged': false, 'module': p['module'], 'bps': p['bps']};
        }
        return {};
      });
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PayoutPctTab(svc: AdminCourierTasksService(callable: fake))),
      ));
      await tester.pumpAndSettle();
      expect(fake.calls.first.$1, 'adminGetCourierTaskPayoutSettings');
      expect(find.text('созланмаган'), findsWidgets, reason: 'agro va collection');
      expect((tester.widget(find.byType(TextField).at(1)) as TextField).controller!.text, '');

      final carpetField = find.byType(TextField).first;
      expect((tester.widget(carpetField) as TextField).controller!.text, '70');
      await tester.enterText(carpetField, '75');
      await tester.tap(find.widgetWithText(FilledButton, 'Сақлаш').first);
      await tester.pumpAndSettle();
      // sabab dialogi: kamida 3 belgi
      await tester.enterText(find.byType(TextField).last, 'ega qarori');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Тасдиқлаш'));
      await tester.pumpAndSettle();

      final set = fake.calls.firstWhere((c) => c.$1 == 'adminSetCourierTaskPayoutPct');
      expect(set.$2, {'module': 'carpet', 'bps': 7500, 'reason': 'ega qarori'});
    });
  });
}
