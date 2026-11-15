// «Бозорлар» 5+6: таксономия модели, динамик майдон текшируви, attrs сериализацияси, карточка қатори,
// сўров филтрлари (count/ring), туман → вилоят.
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
    test('count(): status + market (+ category / imported)', () {
      expect(const MarketFilter(market: 'meat').countFilters, [('status', 'active'), ('market', 'meat')]);
      expect(const MarketFilter(market: 'meat', category: 'beef', importedOnly: true).countFilters,
          [('status', 'active'), ('market', 'meat'), ('category', 'beef'), ('imported', true)]);
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
}
