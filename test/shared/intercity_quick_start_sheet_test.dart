import 'package:ava_gurlan/l10n/app_localizations.dart';
import 'package:ava_gurlan/repositories/schedules_repository.dart';
import 'package:ava_gurlan/shared/widgets/intercity_billing_flow.dart';
import 'package:ava_gurlan/shared/widgets/intercity_quick_start_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tez ishga chiqish oynasi: standart vaqt o'tmishda emas; o'tib ketgan vaqt
/// bilan "Tasdiqlash" to'lov oqimini umuman ishga tushirmaydi.
class _FakeFlow implements IntercityBillingFlow {
  final calls = <DateTime>[];

  @override
  Future<String?> publish(
    BuildContext context, {
    required Color primaryColor,
    required int farePerSeat,
    required String from,
    required String to,
    required String scheduleDate,
    required String startTime,
    required int seats,
    required DateTime departureAt,
  }) async {
    calls.add(departureAt);
    return null; // to'lov oqimi "bekor" — oyna yopilmaydi
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSchedules extends Fake implements SchedulesRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeFlow flow;
  late DateTime now;

  // Til fayli keshi testlar orasida bo'lishiladi: birinchi yuklash fake-async
  // zonasidan tashqarida (haqiqiy async) bajarilsin.
  setUpAll(() async {
    await rootBundle.loadString('assets/lang/uz_Latn.json');
  });

  setUp(() {
    flow = _FakeFlow();
    now = DateTime(2026, 10, 16, 15, 2);
    SharedPreferences.setMockInitialValues({
      'route_from_intercity': 'Хоразм • Гурлан',
      'route_to_intercity': 'Тошкент',
      'intercity_price_intercity': '35000',
      // Kuzatilgan holat: saqlangan/standart 08:00 va "bugun".
      'intercity_departure_hour': '08:00',
    });
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Latn'),
      supportedLocales: const [
        Locale.fromSubtags(languageCode: 'uz', scriptCode: 'Latn'),
      ],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: IntercityQuickStartSheet(
          driverName: 'Ali',
          driverPhone: '+998901234567',
          driverCar: 'Cobalt',
          driverPlate: '01A123BC',
          seats: 4,
          primaryColor: Colors.blue,
          clock: () => now,
          flow: flow,
          schedulesRepo: _FakeSchedules(),
        ),
      ),
    ));
    // Til fayli (rootBundle) va SharedPreferences haqiqiy async talab qiladi.
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
  }

  testWidgets('15:02 da standart 08:00 emas: 15:30 bugun taklif qilinadi',
      (tester) async {
    await pumpSheet(tester);
    expect(find.textContaining('15:30'), findsOneWidget);
    expect(find.textContaining('08:00'), findsNothing);

    await tester.tap(find.text('Tasdiqlash'));
    await tester.pumpAndSettle();
    expect(flow.calls, hasLength(1));
    expect(flow.calls.single, DateTime(2026, 10, 16, 15, 30));
  });

  testWidgets('oyna ochiq turganda vaqt o\'tib ketsa: to\'lov oqimi chaqirilmaydi, sodda xabar',
      (tester) async {
    await pumpSheet(tester);
    expect(find.textContaining('15:30'), findsOneWidget);

    now = DateTime(2026, 10, 16, 16, 0); // foydalanuvchi o'ylab turdi
    await tester.tap(find.text('Tasdiqlash'));
    await tester.pumpAndSettle();

    expect(flow.calls, isEmpty);
    expect(
      find.text(
          "Jo'nash vaqti o'tib ketgan. Keyingi vaqtni yoki «Ertaga»ni tanlang."),
      findsOneWidget,
    );
  });

  testWidgets('kech (23:40): standart "Ertaga" va 08:00', (tester) async {
    now = DateTime(2026, 10, 16, 23, 40);
    await pumpSheet(tester);
    expect(find.textContaining('08:00'), findsOneWidget);

    await tester.tap(find.text('Tasdiqlash'));
    await tester.pumpAndSettle();
    expect(flow.calls.single, DateTime(2026, 10, 17, 8, 0));
  });

  testWidgets('bo\'sh "Qaerdan": xabar uz_Latn da, Kirill qattiq yozuv emas',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpSheet(tester);
    await tester.tap(find.text('Tasdiqlash'));
    await tester.pumpAndSettle();
    expect(find.text('Qaerdan — shaharni kiriting'), findsOneWidget);
    expect(flow.calls, isEmpty);
  });
}
