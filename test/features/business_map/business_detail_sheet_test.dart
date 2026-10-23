import 'package:ava_gurlan/core/theme/app_theme.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_map/domain/business_pin.dart';
import 'package:ava_gurlan/features/business_map/domain/pin_filter.dart';
import 'package:ava_gurlan/features/business_map/widgets/business_detail_sheet.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Локализация делегати АТАЙЛАБ уланмаган: `context.tr` калитнинг ўзини қайтаради.
Future<void> _open(WidgetTester tester, BusinessPin pin) async {
  tester.view.physicalSize = const Size(400 * 2, 1600 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => BusinessDetailSheet.show(context, pin),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

BusinessPin _biz({String phone = '998901234567', String hours = '09:00–21:00'}) => BusinessPin(
      source: BusinessSource.business,
      id: 'b1',
      name: 'Гурлан авто-мойка',
      category: BusinessCategory.auto,
      lat: 41.84,
      lng: 60.39,
      subtitle: 'авто-мойка',
      description: 'Ҳар куни очиқ',
      phone: phone,
      address: 'Гурлан, Навоий кўчаси 5',
      hours: hours,
      website: 'example.uz',
    );

void main() {
  group('BusinessDetailSheet', () {
    testWidgets('тўлиқ маълумот: ном, тур, тавсиф, манзил, иш вақти, телефон, сайт ва тугмалар', (tester) async {
      await _open(tester, _biz());
      expect(find.text('Гурлан авто-мойка'), findsOneWidget);
      expect(find.text('business_cat_auto'), findsOneWidget);
      expect(find.text('авто-мойка'), findsOneWidget);
      expect(find.text('Ҳар куни очиқ'), findsOneWidget);
      expect(find.text('Гурлан, Навоий кўчаси 5'), findsOneWidget);
      expect(find.text('09:00–21:00'), findsOneWidget);
      expect(find.text('998901234567'), findsOneWidget);
      expect(find.text('example.uz'), findsOneWidget);
      expect(find.text('bizmap_call'), findsOneWidget);
      expect(find.text('bizmap_route'), findsOneWidget);
      // оддий объектда модул экрани тугмалари йўқ
      expect(find.text('bizmap_open_menu'), findsNothing);
      expect(find.text('bizmap_open_ev'), findsNothing);
    });

    testWidgets('бўш майдонлар қатор чиқармайди; телефонсиз — «қўнғироқ» йўқ, «йўналиш» бор', (tester) async {
      const pin = BusinessPin(
        source: BusinessSource.business,
        id: 'b2',
        name: 'Дўкон',
        category: BusinessCategory.retail,
        lat: 41.3,
        lng: 69.2,
      );
      await _open(tester, pin);
      expect(find.text('Дўкон'), findsOneWidget);
      expect(find.byIcon(Icons.phone_outlined), findsNothing);
      expect(find.byIcon(Icons.schedule_rounded), findsNothing);
      expect(find.byIcon(Icons.place_outlined), findsNothing);
      expect(find.text('bizmap_call'), findsNothing);
      expect(find.text('bizmap_route'), findsOneWidget);
    });

    testWidgets('кафе: «менюни очиш» тугмаси; зарядка: «станциялар» тугмаси', (tester) async {
      final r = Restaurant.fromMap('r1', {
        'name': 'Ошхона', 'status': 'approved', 'lat': 41.8, 'lng': 60.3, 'contactPhone': '998901112233',
      });
      await _open(tester, BusinessPin.fromRestaurant(r)!);
      expect(find.text('bizmap_open_menu'), findsOneWidget);
      expect(find.text('bizmap_open_ev'), findsNothing);
    });

    testWidgets('EV нуқтаси: ўз экранини очиш тугмаси', (tester) async {
      const pin = BusinessPin(
        source: BusinessSource.evStation,
        id: 'e1',
        name: 'TOK BOR',
        category: BusinessCategory.auto,
        lat: 41.3,
        lng: 69.2,
      );
      await _open(tester, pin);
      expect(find.text('bizmap_open_ev'), findsOneWidget);
      expect(find.text('bizmap_open_menu'), findsNothing);
    });
  });

  group('filterPins / categoriesPresent', () {
    BusinessPin p(String name, BusinessCategory c, {String sub = '', String addr = ''}) => BusinessPin(
          source: BusinessSource.business, id: name, name: name, category: c, lat: 1, lng: 1, subtitle: sub, address: addr,
        );
    final pins = [
      p('Аvto Moyka', BusinessCategory.auto, sub: 'мойка'),
      p('Нон дўкони', BusinessCategory.retail, addr: 'Гурлан'),
      p('Кафе Бахор', BusinessCategory.food),
      p('Улгуржи база', BusinessCategory.wholesale),
    ];

    test('фильтрсиз — ҳаммаси; тур бўйича; ном/кичик тур/манзил бўйича (регистрсиз)', () {
      expect(filterPins(pins).length, 4);
      expect(filterPins(pins, category: BusinessCategory.food).map((e) => e.name), ['Кафе Бахор']);
      expect(filterPins(pins, query: 'НОН').map((e) => e.name), ['Нон дўкони']);
      expect(filterPins(pins, query: 'мойка').map((e) => e.name), ['Аvto Moyka']);
      expect(filterPins(pins, query: 'гурлан').map((e) => e.name), ['Нон дўкони']);
      expect(filterPins(pins, query: '   ').length, 4);
    });

    test('тур ва қидирув бирга; ҳеч нарса топилмаса — бўш', () {
      expect(filterPins(pins, category: BusinessCategory.auto, query: 'нон'), isEmpty);
      expect(filterPins(pins, category: BusinessCategory.retail, query: 'нон').length, 1);
    });

    test('categoriesPresent: фақат бор турлар, enum тартибида', () {
      expect(categoriesPresent(pins), [
        BusinessCategory.retail,
        BusinessCategory.wholesale,
        BusinessCategory.food,
        BusinessCategory.auto,
      ]);
      expect(categoriesPresent(const []), isEmpty);
    });
  });
}
