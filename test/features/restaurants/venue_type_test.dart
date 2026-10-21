// Муассаса тури (D-REST-41, эга 2026-10-19): уй ошпази — «Уй таоми» (автомат); кафе-ресторан эгаси Кафе / Ресторан /
// Чойхона дан бирини ўзи танлайди; фақат ЯНГИ рўйхатдан ўтганларга, ЭСКИ ҳужжатларга тегилмайди; картада ихчам ёрлиқ.

import 'dart:io';

import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_sections.dart';
import 'package:ava_gurlan/features/restaurants/domain/venue_type.dart';
import 'package:ava_gurlan/features/restaurants/merchant/restaurant_form_fields.dart';
import 'package:ava_gurlan/features/restaurants/merchant/restaurant_register_form.dart';
import 'package:ava_gurlan/features/restaurants/widgets/section_dishes_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'restaurants_l10n_harness.dart';
import '../../support/server_checkout.dart';

RestaurantFormData _cafe({String? venue, bool required = true}) => RestaurantFormData(
      name: 'Gurlan osh',
      legalType: 'yatt',
      venueType: venue,
      venueRequired: required,
      address: 'Gurlan',
      lat: 41.84,
      lng: 60.39,
    );

SectionDish _dish({String venue = ''}) => SectionDish(
      restaurantId: 'r1',
      itemId: 'osh',
      name: 'Osh',
      price: 40000,
      restaurantName: 'Gurlan osh',
      venueType: venue,
    );

void main() {
  final l10n = JsonL10nDelegate();
  String tr(String key) => l10n.tr(key);

  group('VenueType', () {
    test('қийматлар: 4 та тўғри, 3 таси танлаш мумкин; noto\'g\'ri/бўш — парс қилинмайди', () {
      expect(VenueType.all, ['home', 'cafe', 'restaurant', 'chaikhana']);
      expect(VenueType.choices, ['cafe', 'restaurant', 'chaikhana']);
      for (final v in ['home', 'cafe', 'restaurant', 'chaikhana']) {
        expect(VenueType.parse(v), v);
      }
      for (final v in [null, '', 'bar', 'HOME', 5, 'home ']) {
        expect(VenueType.parse(v), '', reason: '$v');
      }
    });

    test('СЕРВЕР билан мослик: restaurantRegister `VENUE_CHOICES` ва индекс `VENUE_TYPES`', skip: serverParitySkip, () {
      final orders = File('functions/restaurant_orders.js').readAsStringSync();
      final choices = RegExp(r"const VENUE_CHOICES = \[([^\]]*)\]").firstMatch(orders)![1]!;
      expect(RegExp(r"'(\w+)'").allMatches(choices).map((m) => m[1]).toList(), VenueType.choices);
      final index = File('functions/restaurant_dish_index.js').readAsStringSync();
      final types = RegExp(r"const VENUE_TYPES = Object\.freeze\(\[([^\]]*)\]").firstMatch(index)![1]!;
      expect(RegExp(r"'(\w+)'").allMatches(types).map((m) => m[1]).toList(), VenueType.all);
    });

    test('матн калитлари ҳар тур учун мавжуд (3 тил)', () {
      for (final t in VenueType.all) {
        expect(tr(VenueType.l10nKey(t)), isNot(VenueType.l10nKey(t)), reason: t);
      }
    });
  });

  group('Форма: тур танлаш (янги рўйхатдан ўтиш)', () {
    test('кафе-ресторан: тур мажбурий; танланса — payload да; уй ошпази — юборилмайди', () {
      expect(_cafe().validate(), contains('venue_type'));
      expect(_cafe(venue: 'bar').validate(), contains('venue_type'));
      for (final v in VenueType.choices) {
        final f = _cafe(venue: v);
        expect(f.validate(), isNot(contains('venue_type')), reason: v);
        expect(f.toRegisterPayload()['venueType'], v);
      }
      final home = RestaurantFormData(name: 'Oshxona', legalType: 'individual', venueType: 'cafe', venueRequired: false, address: 'x', lat: 1, lng: 1);
      expect(home.validate(), isNot(contains('venue_type')));
      expect(home.toRegisterPayload().containsKey('venueType'), isFalse, reason: 'уй ошпази: сервер `home` ни ўзи қўяди');
    });

    test('ESKI ресторанни таҳрирлаш: тур талаб қилинмайди ва профил patch да ЙЎҚ (эскиларга тегилмайди)', () {
      final old = _cafe(required: false); // `venueType` йўқ эски ресторан
      expect(old.validate(), isNot(contains('venue_type')));
      expect(old.toProfilePatch().containsKey('venueType'), isFalse);
      final withType = _cafe(venue: 'cafe', required: false);
      expect(withType.toProfilePatch().containsKey('venueType'), isFalse, reason: 'профил таҳририда тур ўзгартирилмайди');
    });

    test('эски клиент: тур танланмаган payload — майдонсиз (сервер: майдон йўқ — рухсат)', () {
      expect(_cafe(required: false).toRegisterPayload().containsKey('venueType'), isFalse);
    });

    testWidgets('тур чиплари: кафе-ресторан формасида 3 та, танланади; уй ошпази формасида (showVenueType: false) йўқ', (t) async {
      final data = _cafe();
      var changed = 0;
      await t.pumpWidget(l10nApp(
        home: Scaffold(
          body: SingleChildScrollView(child: RestaurantFormFields(data: data, onChanged: () => changed++, showVenueType: true, legalTypeOptions: RestaurantFormData.cafeLegalTypes)),
        ),
      ));
      await t.pumpAndSettle();
      for (final v in VenueType.choices) {
        expect(find.byKey(ValueKey('venue-choice-$v')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('venue-choice-home')), findsNothing, reason: '«Уй таоми» танланмайди — автомат');
      await t.ensureVisible(find.byKey(const ValueKey('venue-choice-chaikhana')));
      await t.tap(find.byKey(const ValueKey('venue-choice-chaikhana')));
      await t.pumpAndSettle();
      expect(data.venueType, 'chaikhana');
      expect(changed, greaterThan(0));

      await t.pumpWidget(l10nApp(
        home: Scaffold(body: SingleChildScrollView(child: RestaurantFormFields(data: _cafe(), onChanged: () {}))),
      ));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('venue-choice-cafe')), findsNothing);
    });
  });

  group('Моделлар: эски ҳужжатда тур йўқ', () {
    test('Restaurant.fromMap / SectionDish.fromMap: тўғри қиймат ўқилади, йўқ/нотўғри — бўш', () {
      expect(Restaurant.fromMap('r', {'name': 'a', 'venueType': 'cafe'}).venueType, 'cafe');
      expect(Restaurant.fromMap('r', {'name': 'a'}).venueType, '');
      expect(Restaurant.fromMap('r', {'name': 'a', 'venueType': 'bar'}).venueType, '');
      expect(SectionDish.fromMap({'restaurantId': 'r', 'itemId': 'i', 'venueType': 'home'}).venueType, 'home');
      expect(SectionDish.fromMap({'restaurantId': 'r', 'itemId': 'i'}).venueType, '');
    });
  });

  group('Таом карточкаси: ихчам ёрлиқ', () {
    Future<void> pumpCard(WidgetTester t, SectionDish d) async {
      await t.pumpWidget(l10nApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: SectionDishCard(
              ranked: RankedDish(d),
              section: RestaurantSection.all,
              config: RestaurantSectionsConfig.off,
              onTap: () {},
            ),
          ),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('тури бор таом: ёрлиқ кўринади (ҳар тур — ўз номи билан); тури йўқ (эски) — ёрлиқ ЙЎҚ', (t) async {
      for (final v in VenueType.all) {
        await pumpCard(t, _dish(venue: v));
        final badge = find.byKey(const ValueKey('venue-r1_osh'));
        expect(badge, findsOneWidget, reason: v);
        expect(find.descendant(of: badge, matching: find.text(tr(VenueType.l10nKey(v)))), findsOneWidget, reason: v);
        expect(t.takeException(), isNull);
      }
      await pumpCard(t, _dish());
      expect(find.byKey(const ValueKey('venue-r1_osh')), findsNothing);
    });
  });
}
