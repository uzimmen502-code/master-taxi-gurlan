import 'package:ava_gurlan/features/intercity_taxi/passenger/widgets/intercity_no_rides_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Natijalar sahifasidagi yagona bo'sh holat: sabab + ikki amal.
/// (Til paketi yo'q — `context.tr` kalitning o'zini qaytaradi.)
void main() {
  Future<void> pump(
    WidgetTester tester, {
    String? reason = 'no_driver_today',
    bool isToday = true,
    bool canNext = true,
    VoidCallback? onNext,
    VoidCallback? onAgain,
  }) =>
      tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: IntercityNoRidesView(
            reasonKey: reason,
            isToday: isToday,
            canSearchNextDay: canNext,
            onSearchNextDay: onNext ?? () {},
            onSearchAgain: onAgain ?? () {},
          ),
        ),
      ));

  testWidgets('sarlavha + sabab + ikki amal ko\'rinadi', (tester) async {
    await pump(tester);
    expect(find.text('intercity_no_rides'), findsOneWidget);
    expect(find.text('no_driver_today'), findsOneWidget);
    expect(find.text('intercity_search_tomorrow'), findsOneWidget);
    expect(find.text('intercity_search_again'), findsOneWidget);
    // Takror xabar yo'q: sabab matni faqat bir marta.
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('"Ertaga" va "Qayta qidirish" tegishli amalni chaqiradi',
      (tester) async {
    var next = 0, again = 0;
    await pump(tester, onNext: () => next++, onAgain: () => again++);
    await tester.tap(find.text('intercity_search_tomorrow'));
    expect(next, 1);
    expect(again, 0);
    await tester.tap(find.text('intercity_search_again'));
    expect(again, 1);
    expect(next, 1);
  });

  testWidgets('bugun emas: "Keyingi kunni qidirish"', (tester) async {
    await pump(tester, isToday: false, reason: 'no_driver_on_date');
    expect(find.text('intercity_search_next_day'), findsOneWidget);
    expect(find.text('intercity_search_tomorrow'), findsNothing);
  });

  testWidgets('30 kun chegarasida keyingi kun tugmasi yashirin, qayta qidirish qoladi',
      (tester) async {
    await pump(tester, canNext: false);
    expect(find.text('intercity_search_tomorrow'), findsNothing);
    expect(find.text('intercity_search_next_day'), findsNothing);
    expect(find.text('intercity_search_again'), findsOneWidget);
  });

  testWidgets('sabab noma\'lum bo\'lsa faqat sarlavha', (tester) async {
    await pump(tester, reason: null);
    expect(find.text('intercity_no_rides'), findsOneWidget);
    expect(find.text('no_driver_today'), findsNothing);
  });
}
