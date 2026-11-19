// «Уй-жой бозори» қўшимча майдонлари (эга 2026-11-19): модель, юбориш
// шакли, лента филтри, карточка қатори, тафсилот бўлими.
import 'package:ava_gurlan/features/realty/data/realty_ring_source.dart';
import 'package:ava_gurlan/features/realty/widgets/realty_field_labels.dart';
import 'package:ava_gurlan/models/realty_listing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

RealtyListing _listing(Map<String, dynamic> extra, {String deal = 'sale'}) =>
    RealtyListing.fromMap('L1', {
      'ownerKey': 'K',
      'ownerName': 'Э',
      'deal': deal,
      'tier': 'plain',
      'title': 'Уй',
      'text': 'Матн',
      'areaLat': 41.5,
      'areaLng': 60.6,
      'status': 'active',
      ...extra,
    });

String _tr(String k) => k;

void main() {
  group('RealtyExtras.fromMap', () {
    test('эски ҳужжат — ҳаммаси бўш, валюта UZS', () {
      final x = _listing({}).extras;
      expect(x.propertyType, isNull);
      expect(x.priceCurrency, 'UZS');
      expect(x.utilities, isEmpty);
      expect(x.furnished, isFalse);
    });

    test('нотаниш қийматлар ташлаб юборилади, коммуникация каноник тартибда', () {
      final x = _listing({
        'propertyType': 'castle',
        'renovation': 'euro',
        'priceCurrency': 'EUR',
        'utilities': ['internet', 'wifi', 'gas'],
        'yearBuilt': 2010,
        'deposit': 500,
        'parking': true,
      }).extras;
      expect(x.propertyType, isNull);
      expect(x.renovation, 'euro');
      expect(x.priceCurrency, 'UZS');
      expect(x.utilities, ['gas', 'internet']);
      expect(x.yearBuilt, 2010);
      expect(x.deposit, 500);
      expect(x.parking, isTrue);
    });
  });

  group('RealtyExtras.toPayload', () {
    test('ҳамма 17 калит юборилади; белгиланмагани null (тозалаш)', () {
      final p = const RealtyExtras().toPayload(deal: RealtyDeal.sale, hasPriceAmount: false);
      expect(p.length, 17);
      expect(p.values.every((v) => v == null), isTrue);
    });

    test('ер: хона/таъмир/бино/йил/мебел/балкон юборилмайди, сотих қолади', () {
      final p = const RealtyExtras(
        propertyType: 'land',
        landSotix: 6,
        renovation: 'euro',
        buildingType: 'brick',
        yearBuilt: 2000,
        furnished: true,
        balcony: true,
        parking: true,
      ).toPayload(deal: RealtyDeal.sale, hasPriceAmount: true);
      expect(p['landSotix'], 6);
      expect(p['renovation'], isNull);
      expect(p['buildingType'], isNull);
      expect(p['yearBuilt'], isNull);
      expect(p['furnished'], isNull);
      expect(p['balcony'], isNull);
      expect(p['parking'], isTrue);
      expect(p['priceCurrency'], 'UZS');
    });

    test('квартирада сотих йўқ; сотувда ижара шартлари йўқ; нархсиз валюта йўқ', () {
      final p = const RealtyExtras(
        propertyType: 'apartment',
        landSotix: 5,
        rentPeriod: 'month',
        deposit: 100,
        priceCurrency: 'USD',
      ).toPayload(deal: RealtyDeal.sale, hasPriceAmount: false);
      expect(p['landSotix'], isNull);
      expect(p['rentPeriod'], isNull);
      expect(p['deposit'], isNull);
      expect(p['priceCurrency'], isNull);
    });

    test('ижара: муддат, депозит ва USD юборилади', () {
      final p = const RealtyExtras(
        propertyType: 'house',
        rentPeriod: 'day',
        deposit: 300,
        priceCurrency: 'USD',
        utilities: ['gas', 'water'],
        negotiable: true,
      ).toPayload(deal: RealtyDeal.rent, hasPriceAmount: true);
      expect(p['rentPeriod'], 'day');
      expect(p['deposit'], 300);
      expect(p['priceCurrency'], 'USD');
      expect(p['utilities'], ['gas', 'water']);
      expect(p['negotiable'], isTrue);
      expect(p['mortgage'], isNull);
    });

    test('чегара: расм 10 та, сотих 0.1..10000', () {
      expect(RealtyFieldOptions.maxImages, 10);
      expect(RealtyFieldOptions.landSotixMin, 0.1);
      expect(RealtyFieldOptions.landSotixMax, 10000);
    });
  });

  group('лента филтри (тур)', () {
    test('тур танланса фақат шу тур; тури йўқ эски эълон яширилади', () {
      const f = RealtyRingFilter(propertyType: 'land');
      expect(f.shows(_listing({'propertyType': 'land'})), isTrue);
      expect(f.shows(_listing({'propertyType': 'house'})), isFalse);
      expect(f.shows(_listing({})), isFalse);
      expect(const RealtyRingFilter().shows(_listing({})), isTrue);
      expect(f == const RealtyRingFilter(propertyType: 'land'), isTrue);
      expect(f == const RealtyRingFilter(), isFalse);
    });
  });

  group('карточка қатори', () {
    test('тур + specs + сотих; эски ёзувда — аввалги specs', () {
      final r = _listing({'propertyType': 'house', 'rooms': 4, 'areaM2': 120, 'landSotix': 6});
      expect(realtyCardSpecs(_tr, r), 'realty_type_house · 4 хона · 120 м² · 6 realty_unit_sotix');
      final old = _listing({'rooms': 2});
      expect(realtyCardSpecs(_tr, old), old.specsLabel);
    });

    test('пул: USD — \$ олдида, сўм — орқада', () {
      expect(realtyMoney(_tr, 45000, 'USD'), '\$45 000');
      expect(realtyMoney(_tr, 1500000, 'UZS'), '1 500 000 realty_currency_uzs');
    });
  });

  group('тафсилот бўлими', () {
    testWidgets('эски эълон — бўлим чизилмайди', (t) async {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: RealtyExtrasSection(listing: _listing({})))));
      expect(find.byKey(const ValueKey('realty_extras_section')), findsNothing);
    });

    testWidgets('тўлдирилган майдонлар ва белгилар кўрсатилади', (t) async {
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RealtyExtrasSection(
            listing: _listing({
              'propertyType': 'apartment',
              'renovation': 'euro',
              'yearBuilt': 2015,
              'utilities': ['gas'],
              'deposit': 200,
              'rentPeriod': 'month',
              'priceCurrency': 'USD',
              'furnished': true,
              'mortgage': true,
            }, deal: 'rent'),
          ),
        ),
      ));
      expect(find.byKey(const ValueKey('realty_extras_section')), findsOneWidget);
      expect(find.text('realty_type_apartment'), findsOneWidget);
      expect(find.text('realty_renovation_euro'), findsOneWidget);
      expect(find.text('2015'), findsOneWidget);
      expect(find.text('realty_utility_gas'), findsOneWidget);
      expect(find.text('\$200'), findsOneWidget);
      expect(find.text('realty_rent_month'), findsOneWidget);
      expect(find.text('realty_flag_furnished'), findsOneWidget);
      expect(find.text('realty_flag_mortgage'), findsOneWidget);
      expect(find.text('realty_flag_barter'), findsNothing);
    });
  });
}
