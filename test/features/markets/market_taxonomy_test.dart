// «Бозорлар» 5+6: таксономия модели, динамик майдон текшируви, attrs сериализацияси, карточка қатори,
// сўров филтрлари (count/ring), туман → вилоят.
import 'dart:convert';
import 'dart:io';

import 'package:ava_gurlan/core/geo/geo_context.dart';
import 'package:ava_gurlan/core/service_config_holder.dart';
import 'package:ava_gurlan/features/markets/data/market_listings_source.dart';
import 'package:ava_gurlan/features/markets/data/market_taxonomy_repository.dart';
import 'package:ava_gurlan/features/markets/domain/market_taxonomy.dart';
import 'package:ava_gurlan/features/tv_market/domain/price_unit.dart';
import 'package:ava_gurlan/features/tv_market/models/tv_shop.dart';
import 'package:ava_gurlan/models/geo_area.dart' show GeoDistrict;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'taxonomy_fixture.dart';

// ignore: subtype_of_sealed_class
class _Doc implements DocumentSnapshot<Map<String, dynamic>> {
  _Doc(this.id, this._data);
  @override
  final String id;
  final Map<String, dynamic> _data;
  @override
  Map<String, dynamic>? data() => _data;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  final t = kTaxonomyV1;
  final livestock = t.market('livestock')!;
  final auto = t.market('auto')!;
  final meat = t.market('meat')!;
  final farm = t.market('farm')!;

  group('модел', () {
    // Эга 2026-11-16: v2 — 6 бозор; Электроника/Маиший техника: «Барчаси»+чиплар, Импорт йўқ, таб эмас.
    test('v3: 6 бозор тартибда; electronics/appliances шакли', () {
      final v3 = kTaxonomyV3;
      expect(v3.ordered.map((m) => m.id), ['livestock', 'auto', 'meat', 'farm', 'electronics', 'appliances']);
      for (final id in ['electronics', 'appliances']) {
        final m = v3.market(id)!;
        expect(m.moduleId, '${id}_market');
        expect(m.hasCategoryChoice, isTrue, reason: id);
        expect(m.usesTabs, isFalse, reason: id);
        expect(m.hasImported, isFalse, reason: id);
        expect(m.priceUnits, [PriceUnit.fixed, PriceUnit.piece], reason: id);
      }
    });
    test('версия, тартиб, бирликлар, битта бўлим', () {
      expect(t.version, 1);
      expect(t.ordered.map((m) => m.id), ['livestock', 'auto', 'meat', 'farm']);
      expect(livestock.priceUnits, [PriceUnit.fixed, PriceUnit.piece]);
      expect(meat.priceUnits, [PriceUnit.kg]);
      expect(farm.priceUnits, [PriceUnit.kg, PriceUnit.ton, PriceUnit.piece]);
      expect(livestock.autoCategory, 'all');
      expect(livestock.hasCategoryChoice, isFalse);
      expect(auto.usesTabs, isTrue);
      expect(farm.usesTabs, isFalse);
      expect(meat.hasImported, isTrue);
      expect(farm.hasImported, isFalse);
      expect(meat.label('ru'), 'Мясной рынок');
    });

    test('бузилган шакл ташланади: номаълум тур, optionsсиз select, moduleIdсиз бозор, номаълум бирлик', () {
      final x = MarketTaxonomy.fromMap({
        'version': 'x',
        'markets': {
          'a': {
            'moduleId': 'a_m',
            'categories': [
              {'id': 'c'},
            ],
            'fields': [
              {'key': 'f1', 'type': 'color'},
              {'key': 'f2', 'type': 'select', 'options': []},
              {'key': 'f3', 'type': 'int'},
            ],
            'priceUnits': ['week', 'kg'],
          },
          'b': {'categories': []},
        },
      });
      expect(x.version, 0);
      expect(x.markets.keys, ['a']);
      expect(x.market('a')!.fields.map((f) => f.key), ['f3']);
      expect(x.market('a')!.priceUnits, [PriceUnit.kg]);
      expect(MarketTaxonomy.fromMap(null).markets, isEmpty);
    });

    test('майдонлар бўлим бўйича филтрланади', () {
      expect(auto.fieldsFor('cars').map((f) => f.key), ['brand', 'year']);
      expect(auto.fieldsFor('parts').map((f) => f.key), ['fits_car', 'condition']);
      expect(livestock.fieldsFor('all').length, 6);
    });
  });

  group('текширув', () {
    MarketField f(MarketDef m, String k) => m.fields.firstWhere((x) => x.key == k);

    test('int: рақам, min/max чегаралари (boundary)', () {
      final age = f(livestock, 'age_months');
      expect(age.validate('0'), isNull);
      expect(age.validate('600'), isNull);
      expect(age.validate('601'), MarketFieldError.max);
      expect(age.validate('-1'), MarketFieldError.min);
      expect(f(livestock, 'count').validate('0'), MarketFieldError.min);
      expect(age.validate('abc'), MarketFieldError.number);
      expect(age.validate(''), isNull); // ихтиёрий
    });

    test('text maxLen, select option, bool, date', () {
      expect(f(livestock, 'breed').validate('x' * 60), isNull);
      expect(f(livestock, 'breed').validate('x' * 61), MarketFieldError.maxLen);
      expect(f(livestock, 'sex').validate('male'), isNull);
      expect(f(livestock, 'sex').validate('cat'), MarketFieldError.option);
      expect(f(livestock, 'pregnant').validate(false), isNull);
      expect(f(meat, 'slaughter_date').validate('2026-11-15'), isNull);
      expect(f(meat, 'slaughter_date').validate('2026-02-30'), MarketFieldError.number);
    });

    test('required: бўш — хато; тўлдирилган — тўғри', () {
      const req = MarketField(key: 'k', type: MarketFieldType.text, names: {}, required: true);
      expect(req.validate(''), MarketFieldError.required);
      expect(req.validate(null), MarketFieldError.required);
      expect(req.validate('a'), isNull);
      const reqBool = MarketField(key: 'b', type: MarketFieldType.bool, names: {}, required: true);
      expect(reqBool.validate(false), MarketFieldError.required);
      expect(validateAttrs(livestock, 'all', {'age_months': '700', 'breed': 'Ҳисори'}).keys, ['age_months']);
    });
  });

  group('attrs сериализацияси', () {
    test('турли қийматлар; бўш/белгиланмаган ва бошқа бўлим майдонлари ёзилмайди; сана ISO', () {
      final a = serializeAttrs(livestock, 'all', {
        'breed': '  Ҳисори ',
        'age_months': '24',
        'sex': 'female',
        'count': '',
        'pregnant': false,
        'weight_kg': null,
      });
      expect(a, {'breed': 'Ҳисори', 'age_months': 24, 'sex': 'female'});
      expect(a['age_months'], isA<int>());
      expect(serializeAttrs(livestock, 'all', {'pregnant': true}), {'pregnant': true});
      expect(serializeAttrs(auto, 'parts', {'brand': 'Chevrolet', 'fits_car': 'Nexia'}), {'fits_car': 'Nexia'});
      expect(serializeAttrs(meat, 'beef', {'slaughter_date': '2026-11-14'}), {'slaughter_date': '2026-11-14'});
      expect(isoDate(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('TvShopItem: бозор майдонлари round-trip; Аралашда ёзилмайди', () {
      const item = TvShopItem(
        id: 'a',
        ownerPhone: '998901111111',
        ownerName: 'x',
        title: 'Сигир',
        price: 9000000,
        photoUrl: 'u',
        kind: 'product',
        districtId: 'gurlan',
        districtLabel: 'Гурлан',
        market: 'livestock',
        category: 'all',
        attrs: {'age_months': 24},
        regionId: 'xorazm',
        taxonomyVersion: 1,
      );
      final m = item.toMap();
      expect(m['market'], 'livestock');
      expect(m['category'], 'all');
      expect(m['attrs'], {'age_months': 24});
      expect(m['regionId'], 'xorazm');
      expect(m['taxonomyVersion'], 1);
      expect(m.containsKey('imported'), isFalse);
      final back = TvShopItem.fromFirestore(_Doc('a', {...m, 'createdAt': null, 'imported': true}));
      expect(back.category, 'all');
      expect(back.attrs, {'age_months': 24});
      expect(back.imported, isTrue);
      expect(back.taxonomyVersion, 1);
      const plain = TvShopItem(
          id: 'b', ownerPhone: '1', ownerName: '', title: 't', price: 1, photoUrl: '', kind: 'product',
          districtId: '', districtLabel: '');
      for (final k in ['market', 'category', 'attrs', 'imported', 'regionId', 'taxonomyVersion']) {
        expect(plain.toMap().containsKey(k), isFalse, reason: k);
      }
    });
  });

  group('кўрсатиш', () {
    test('карточка қатори: биринчи 3 тўлдирилган майдон, select номи, bool — фақат номи, тил', () {
      final attrs = {'breed': 'Ҳисори', 'age_months': 24, 'sex': 'female', 'count': 3};
      expect(marketAttrsLine(livestock, 'all', attrs, 'uz_Cyrl'), 'Зоти: Ҳисори · Ёши (ой): 24 · Жинси: Урғочи');
      expect(marketAttrsLine(livestock, 'all', {'sex': 'male', 'pregnant': true}, 'ru'), 'Пол: Самец · Стельная');
      expect(marketAttrsLine(livestock, 'all', {'sex': 'bogus'}, 'uz_Cyrl'), '');
      expect(marketAttrsLine(meat, 'beef', {'slaughter_date': '2026-11-14'}, 'uz_Cyrl'), 'Сўйилган санаси: 14.11.2026');
    });

    test('детал қаторлари: bool → «Ҳа» матни; номаълум майдон ташланади', () {
      final rows = marketAttrRows(livestock, 'all', {'pregnant': true, 'zzz': 1, 'age_months': 5}, 'uz_Latn', yes: 'Ha');
      expect(rows, [('Yoshi (oy)', '5'), ("Bo'g'oz", 'Ha')]);
    });

    test('клиент нарх филтри', () {
      expect(priceInRange(0, null, null), isTrue);
      expect(priceInRange(0, 1, null), isFalse);
      expect(priceInRange(100, 100, 100), isTrue);
      expect(priceInRange(99, 100, null), isFalse);
      expect(priceInRange(101, null, 100), isFalse);
    });
  });

  group('сўров филтрлари', () {
    test('ҳалқа сўрови тенглик филтрлари (count() 2026-11-16 да олиб ташланди)', () {
      expect(const MarketFilter(market: 'farm', category: 'fruits').equals, {'market': 'farm', 'category': 'fruits'});
      expect(const MarketFilter(market: 'meat', importedOnly: true).equals, {'market': 'meat', 'imported': true});
    });
  });

  group('туман → вилоят', () {
    tearDown(() {
      ServiceConfigHolder.resetForTest();
      GeoContext.resetForTest();
    });

    test('профил тумани — ўқишсиз; бошқа туман — geo_districts; хато — бўш', () async {
      ServiceConfigHolder.setForTest(districtId: 'gurlan', regionId: 'xorazm');
      var reads = 0;
      Future<GeoDistrict?> fetch(String id) async {
        reads++;
        if (id == 'bad') throw StateError('offline');
        return GeoDistrict(id: id, regionId: 'samarqand', name: 'X', active: true);
      }

      expect(await resolveRegionIdForDistrict('gurlan', fetchDistrict: fetch), 'xorazm');
      expect(reads, 0);
      expect(await resolveRegionIdForDistrict('urgut', fetchDistrict: fetch), 'samarqand');
      expect(await resolveRegionIdForDistrict('bad', fetchDistrict: fetch), '');
      expect(await resolveRegionIdForDistrict('', fetchDistrict: fetch), '');
    });
  });

  group('таксономия кеши', () {
    tearDown(() {
      MarketTaxonomyRepository.loaderOverride = null;
      MarketTaxonomyRepository.setForTest(null);
    });

    test('сеансда бир марта ўқилади; хато кешланмайди', () async {
      var reads = 0;
      var fail = true;
      MarketTaxonomyRepository.setForTest(null);
      MarketTaxonomyRepository.loaderOverride = () async {
        reads++;
        if (fail) throw StateError('offline');
        return kTaxonomyDocV1;
      };
      await expectLater(MarketTaxonomyRepository.load(), throwsStateError);
      fail = false;
      final a = MarketTaxonomyRepository.load();
      final b = MarketTaxonomyRepository.load();
      expect((await a).version, 1);
      expect(identical(await a, await b), isTrue);
      await MarketTaxonomyRepository.load();
      expect(reads, 2);
    });
  });

  // Эга 2026-11-19: ёш «йил + ой», мошина сарлавҳаси, каробка ўлчамлари, «Ўз автомобилим», v5 таксономия.
  group('2026-11-19', () {
    String Function(String) trOf(String lang) {
      final m = jsonDecode(File('assets/lang/$lang.json').readAsStringSync()) as Map<String, dynamic>;
      return (k) => (m[k] as String?) ?? k;
    }

    final cyr = trOf('uz_Cyrl'), lat = trOf('uz_Latn'), ru = trOf('ru');

    test('formatAgeMonths: «1 йилу 7 ойлик», «2 ёшли», «7 ойлик» (3 тил)', () {
      expect(formatAgeMonths(19, cyr), '1 йилу 7 ойлик');
      expect(formatAgeMonths(24, cyr), '2 ёшли');
      expect(formatAgeMonths(7, cyr), '7 ойлик');
      expect(formatAgeMonths(19, lat), '1 yilu 7 oylik');
      expect(formatAgeMonths(24, lat), '2 yoshli');
      expect(formatAgeMonths(7, lat), '7 oylik');
      expect(formatAgeMonths(19, ru), '1 год 7 мес.');
      expect(formatAgeMonths(7, ru), '7 мес.');
    });

    test('formatAgeMonths: рус кўплиги 1 год · 2–4 года · 5+ лет · 11–14 лет · 21 год; чегаралар', () {
      expect(formatAgeMonths(12, ru), '1 год');
      expect(formatAgeMonths(24, ru), '2 года');
      expect(formatAgeMonths(48, ru), '4 года');
      expect(formatAgeMonths(60, ru), '5 лет');
      expect(formatAgeMonths(11 * 12, ru), '11 лет');
      expect(formatAgeMonths(14 * 12 + 3, ru), '14 лет 3 мес.');
      expect(formatAgeMonths(21 * 12, ru), '21 год');
      expect(formatAgeMonths(22 * 12 + 1, ru), '22 года 1 мес.');
      expect(formatAgeMonths(0, cyr), '0 ойлик');
      expect(formatAgeMonths(11, cyr), '11 ойлик');
      expect(formatAgeMonths(-1, cyr), '');
    });

    test('карточка/детал: ёш махсус кўриниш; tr берилмаса — аввалги', () {
      final v5 = kTaxonomyV5.market('livestock')!;
      expect(marketAttrsLine(v5, 'cattle', {'breed': 'Ҳисори', 'age_months': 19}, 'uz_Cyrl', tr: cyr),
          'Зоти: Ҳисори · 1 йилу 7 ойлик');
      expect(marketAttrRows(v5, 'cattle', {'age_months': 24}, 'ru', yes: 'Да', tr: ru), [('Возраст (лет, мес.)', '2 года')]);
      expect(marketAttrsLine(v5, 'cattle', {'age_months': 19}, 'uz_Cyrl'), 'Ёши (ой): 19');
    });

    test('каробка: детал «40 × 30 × 25 см» битта қатор; қисман — кўрсатилмайди', () {
      final el = kTaxonomyV5.market('electronics')!;
      final full = {'brand': 'Samsung', 'box_w_cm': 40, 'box_l_cm': 30, 'box_h_cm': 25};
      expect(marketAttrRows(el, 'phones', full, 'uz_Cyrl', yes: 'Ҳа', tr: cyr),
          [('Марка', 'Samsung'), ('Каробка ўлчамлари', '40 × 30 × 25 см')]);
      expect(marketAttrRows(el, 'phones', full, 'uz_Latn', yes: 'Ha', tr: lat).last, ("Karobka o'lchamlari", '40 × 30 × 25 sm'));
      expect(marketAttrRows(el, 'phones', {'box_w_cm': 40, 'box_l_cm': 30}, 'ru', yes: 'Да', tr: ru), isEmpty);
      expect(marketAttrsLine(el, 'phones', full, 'ru', tr: ru), 'Марка: Samsung · 40 × 30 × 25 см');
    });

    test('validateAttrs: каробка ё учаласи, ё ҳеч бири (incomplete); v4 да қоида йўқ', () {
      final el = kTaxonomyV5.market('electronics')!;
      expect(validateAttrs(el, 'phones', const {}), isEmpty);
      expect(validateAttrs(el, 'phones', {'box_w_cm': '40', 'box_l_cm': '30', 'box_h_cm': '25'}), isEmpty);
      expect(validateAttrs(el, 'phones', {'box_w_cm': '40'}),
          {'box_l_cm': MarketFieldError.incomplete, 'box_h_cm': MarketFieldError.incomplete});
      expect(validateAttrs(el, 'phones', {'box_w_cm': '0', 'box_l_cm': '1', 'box_h_cm': '1000'}),
          {'box_w_cm': MarketFieldError.min});
      expect(hasBoxDims(el.fields), isTrue);
      expect(hasBoxDims(kTaxonomyV3.market('electronics')!.fields), isFalse);
    });

    test('composeAutoTitle / autoBrandModelValid', () {
      expect(composeAutoTitle(brand: ' Chevrolet ', model: 'Cobalt', year: '2021'), 'Chevrolet Cobalt 2021');
      expect(composeAutoTitle(brand: 'Lada', model: '', year: ''), 'Lada');
      expect(composeAutoTitle(brand: 'Kia  Motors', model: 'K5', year: null), 'Kia Motors K5');
      expect(autoBrandModelValid('', ''), isFalse);
      expect(autoBrandModelValid('A', ' '), isFalse);
      expect(autoBrandModelValid('A', 'B'), isTrue);
      expect(autoBrandModelValid('', 'K5'), isTrue);
    });

    test('ownCarFormValues: марка/модель/йил/ёқилғи; cng→methane, petrol; номаълум ёқилғи — ёзилмайди', () {
      final auto = kTaxonomyV5.market('auto')!;
      expect(
          ownCarFormValues(auto, 'cars',
              {'carBrand': 'Chevrolet', 'carModel': 'Cobalt', 'carYear': '2021', 'carFuelType': 'cng'}),
          {'brand': 'Chevrolet', 'model': 'Cobalt', 'year': '2021', 'fuel': 'methane'});
      expect(ownCarFormValues(auto, 'cars', {'carModel': 'Nexia', 'carFuelType': 'petrol'}),
          {'model': 'Nexia', 'fuel': 'petrol'});
      expect(ownCarFormValues(auto, 'cars', {'carBrand': 'X', 'carYear': '', 'carFuelType': 'kerosene'}), {'brand': 'X'});
      expect(ownCarFormValues(auto, 'parts', {'carBrand': 'X'}), isEmpty, reason: 'эҳтиёт қисмда марка майдони йўқ');
    });

    test('v5 таксономия: Мол 5 бўлим (all йўқ), Мошина номлари, v4 мослиги', () {
      final v5 = kTaxonomyV5;
      expect([for (final c in v5.market('livestock')!.categories) c.id], ['cattle', 'sheep_goat', 'horse', 'poultry', 'other']);
      expect(v5.market('livestock')!.hasCategoryChoice, isTrue);
      expect(v5.market('auto')!.category('cars')!.label('uz_Cyrl'), 'Авто');
      expect(v5.market('auto')!.category('tech')!.label('ru'), 'Спецтехника');
      // v4/v1: Мол битта бўлим (`all`) — аввалгидек.
      expect(livestock.autoCategory, 'all');
      // Эски `all` эълони v5 карточкасида майдонлари билан кўринади (бўлим чекловисиз майдонлар).
      expect(marketAttrsLine(v5.market('livestock')!, 'all', {'breed': 'Ҳисори'}, 'uz_Cyrl'), 'Зоти: Ҳисори');
    });
  });
}
