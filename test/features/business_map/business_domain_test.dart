import 'dart:io';
import 'dart:math';

import 'package:ava_gurlan/features/business_map/data/business_pin_loader.dart';
import 'package:ava_gurlan/features/business_map/domain/business.dart';
import 'package:ava_gurlan/features/business_map/domain/business_category.dart';
import 'package:ava_gurlan/features/business_map/domain/business_pin.dart';
import 'package:ava_gurlan/core/geo/viewport_cells.dart';
import 'package:ava_gurlan/features/restaurants/domain/restaurant_models.dart';
import 'package:ava_gurlan/features/wholesale/models/wholesale_seller.dart';
import 'package:ava_gurlan/models/ev_charging_station.dart';
import 'package:ava_gurlan/utils/geo_hash.dart';
import 'package:flutter_test/flutter_test.dart';

BusinessPin _pin(String id, double lat, double lng) => BusinessPin(
      source: BusinessSource.business,
      id: id,
      name: id,
      category: BusinessCategory.retail,
      lat: lat,
      lng: lng,
    );

void main() {
  group('BusinessCategory', () {
    test('Dart рўйхати сервердаги CATEGORIES билан бир хил (тартиб билан)', () {
      final js = File('functions/business_directory.js').readAsStringSync();
      final m = RegExp(r'const CATEGORIES = Object\.freeze\(\[([\s\S]*?)\]\)').firstMatch(js);
      expect(m, isNotNull, reason: 'functions/business_directory.js да CATEGORIES топилмади');
      final server = RegExp(r"'([a-z_]+)'").allMatches(m!.group(1)!).map((x) => x.group(1)!).toList();
      expect(BusinessCategory.wires, server);
    });

    test('эски 14 талик қийматлар сервердаги LEGACY_CATEGORIES билан бир хил ўгирилади', () {
      final js = File('functions/business_directory.js').readAsStringSync();
      final m = RegExp(r'const LEGACY_CATEGORIES = Object\.freeze\(\{([\s\S]*?)\}\)').firstMatch(js);
      expect(m, isNotNull, reason: 'functions/business_directory.js да LEGACY_CATEGORIES топилмади');
      final server = {
        for (final x in RegExp(r"([a-z_]+): '([a-z_]+)'").allMatches(m!.group(1)!)) x.group(1)!: x.group(2)!,
      };
      expect({for (final e in BusinessCategory.legacyWires.entries) e.key: e.value.wire}, server);
      for (final legacy in server.keys) {
        expect(BusinessCategory.wires, isNot(contains(legacy)), reason: legacy);
      }
    });

    test('fromWire: номаълум/бўш/null — other (синмайди); эски қиймат — янгиси', () {
      expect(BusinessCategory.fromWire('auto'), BusinessCategory.auto);
      expect(BusinessCategory.fromWire('real_estate'), BusinessCategory.realEstate);
      expect(BusinessCategory.fromWire('home_services'), BusinessCategory.personal);
      expect(BusinessCategory.fromWire('wholesale'), BusinessCategory.retail);
      expect(BusinessCategory.fromWire('leisure'), BusinessCategory.sport);
      expect(BusinessCategory.fromWire('it_media'), BusinessCategory.it);
      expect(BusinessCategory.fromWire('yoq'), BusinessCategory.other);
      expect(BusinessCategory.fromWire(''), BusinessCategory.other);
      expect(BusinessCategory.fromWire(null), BusinessCategory.other);
    });

    test('ҳар бир туру калити ва иконкаси бор, wire такрорсиз', () {
      expect(BusinessCategory.wires.toSet().length, BusinessCategory.values.length);
      for (final c in BusinessCategory.values) {
        expect(c.labelKey, 'business_cat_${c.wire}');
      }
    });
  });

  group('Business', () {
    test('tryFromMap: тўлиқ ҳужжат', () {
      final b = Business.tryFromMap('id1', {
        'ownerId': '998901234567',
        'name': ' Дўкон ',
        'category': 'retail',
        'phone': '998901234567',
        'lat': 41.8,
        'lng': 60.3,
        'subtype': 'озиқ-овқат',
        'districtId': 'd1',
        'regionId': 'r1',
      })!;
      expect(b.name, 'Дўкон');
      expect(b.category, BusinessCategory.retail);
      expect(b.lat, 41.8);
      expect(b.districtId, 'd1');
    });

    test('tryFromMap: уланган ресторан (restaurantId) ўқилади; йўқ/бўш/сон — уланмаган', () {
      Business b(Object? rid) => Business.tryFromMap('x', {
            'name': 'Кафе', 'category': 'food', 'lat': 41.0, 'lng': 60.0, 'restaurantId': rid,
          })!;
      expect(b(' r1 ').restaurantId, 'r1');
      expect(b(' r1 ').hasRestaurant, isTrue);
      for (final v in [null, '', '  ', 42]) {
        expect(b(v).restaurantId, '', reason: '$v');
        expect(b(v).hasRestaurant, isFalse, reason: '$v');
      }
      expect(b('r1').toCallable().containsKey('restaurantId'), isFalse, reason: 'фақат сервер ёзади (18-банд)');
    });

    test('tryFromMap: координата йўқ/нотўғри — null (харита синмайди)', () {
      expect(Business.tryFromMap('x', {'name': 'a', 'category': 'retail'}), isNull);
      expect(Business.tryFromMap('x', {'lat': '41', 'lng': 60}), isNull);
    });

    test('toCallable: сервер қабул қиладиган майдонлар, ownerId/status/geohash ЙЎҚ (18-банд)', () {
      final b = Business.tryFromMap('x', {
        'ownerId': 'o', 'name': 'Nom', 'category': 'auto', 'phone': '998901234567', 'lat': 41.0, 'lng': 60.0,
      })!;
      final m = b.toCallable();
      expect(m.keys.toSet(), {
        'name', 'category', 'subtype', 'description', 'phone', 'address', 'lat', 'lng',
        'regionId', 'districtId', 'openingHours', 'website',
      });
      expect(m['category'], 'auto');
    });
  });

  group('ViewportCells', () {
    test('кичик камера — бир нечта катак; ҳар бир нуқтанинг geohash4 рўйхатда', () {
      const south = 41.7, north = 41.95, west = 60.2, east = 60.6;
      final cells = ViewportCells.forBounds(south: south, west: west, north: north, east: east)!;
      expect(cells.length, lessThanOrEqualTo(ViewportCells.maxCells));
      final rnd = Random(7);
      for (var i = 0; i < 500; i++) {
        final lat = south + rnd.nextDouble() * (north - south);
        final lng = west + rnd.nextDouble() * (east - west);
        expect(cells, contains(GeoHash.encode(lat, lng, precision: 4)), reason: '$lat,$lng');
      }
    });

    test('чегара нуқталар (бурчаклар) ҳам қопланади', () {
      const south = 40.1, north = 41.0, west = 66.0, east = 67.2;
      final cells = ViewportCells.forBounds(south: south, west: west, north: north, east: east)!;
      for (final p in [(south, west), (south, east), (north, west), (north, east)]) {
        expect(cells, contains(GeoHash.encode(p.$1, p.$2, precision: 4)), reason: '$p');
      }
    });

    test('бутун мамлакат масштаби — null (яқинлаштиринг), ўқиш йўқ', () {
      expect(ViewportCells.forBounds(south: 37, west: 56, north: 45, east: 73), isNull);
    });

    test('чегара: 30 катакдан ошмайди; нотўғри бўлак — null', () {
      expect(ViewportCells.forBounds(south: 41, west: 60, north: 40, east: 61), isNull);
      expect(ViewportCells.forBounds(south: 41, west: 62, north: 42, east: 61), isNull);
      final r = ViewportCells.forBounds(south: 41, west: 60, north: 41.01, east: 60.01)!;
      expect(r.length, inInclusiveRange(1, 4));
    });
  });

  group('BusinessPin', () {
    test('Restaurant: тасдиқланган + координатали — food; бошқаси — null', () {
      final ok = Restaurant.fromMap('r1', {
        'name': 'Ошхона', 'status': 'approved', 'lat': 41.8, 'lng': 60.3, 'contactPhone': '998901112233',
        'address': 'Гурлан', 'cuisineTags': ['uzbek', 'grill'],
      });
      final pin = BusinessPin.fromRestaurant(ok)!;
      expect(pin.category, BusinessCategory.food);
      expect(pin.source, BusinessSource.restaurant);
      expect(pin.subtitle, 'uzbek, grill');
      expect(pin.key, 'restaurant:r1');
      expect(BusinessPin.fromRestaurant(Restaurant.fromMap('r2', {'name': 'x', 'status': 'applied', 'lat': 1.0, 'lng': 2.0})), isNull);
      expect(BusinessPin.fromRestaurant(Restaurant.fromMap('r3', {'name': 'x', 'status': 'approved'})), isNull);
    });

    test('WholesaleSeller: фақат тасдиқланган ва координатали', () {
      WholesaleSeller s(String status, {double? lat, double? lng}) => WholesaleSeller(
            phone: '998901234567', companyName: 'Sunlight', approvalStatus: status, lat: lat, lng: lng,
          );
      final pin = BusinessPin.fromWholesaleSeller(s('approved', lat: 41.3, lng: 69.2))!;
      expect(pin.category, BusinessCategory.retail); // «Савдо ва дўконлар» (30 тур)
      expect(pin.id, '998901234567');
      expect(BusinessPin.fromWholesaleSeller(s('pending', lat: 41.3, lng: 69.2)), isNull);
      expect(BusinessPin.fromWholesaleSeller(s('approved')), isNull);
    });

    test('EV: фаол станция — auto; номсиз бўлса оператор номи; ноактив — null', () {
      EvChargingStation st({bool active = true, String? name, String? op}) => EvChargingStation(
            id: 'e1', latitude: 41.3, longitude: 69.2, geohash: 'tn', chargingTypes: const [], connectors: const [],
            status: 'working', verificationStatus: 'community', confirmationCount: 0, reportCount: 0,
            createdBy: 'u', isActive: active, name: name, operatorName: op, powerKw: 60,
          );
      final pin = BusinessPin.fromEvStation(st(op: 'TOK BOR'))!;
      expect(pin.category, BusinessCategory.auto);
      expect(pin.name, 'TOK BOR');
      expect(pin.subtitle, '60 kW');
      expect(BusinessPin.fromEvStation(st(name: 'Станция', op: 'TOK BOR'))!.subtitle, 'TOK BOR · 60 kW');
      expect(BusinessPin.fromEvStation(st(active: false)), isNull);
    });

    test('key: манбалар орасида бир хил ID тўқнашмайди', () {
      final a = BusinessPin(source: BusinessSource.business, id: '1', name: 'a', category: BusinessCategory.other, lat: 1, lng: 1);
      final b = BusinessPin(source: BusinessSource.restaurant, id: '1', name: 'b', category: BusinessCategory.food, lat: 1, lng: 1);
      expect(a.key, isNot(b.key));
    });
  });

  group('BusinessPinLoader.capNearest', () {
    test('чегарадан кам — ўзгармайди; кўп бўлса — марказга энг яқинлари', () {
      final pins = [for (var i = 0; i < 10; i++) _pin('p$i', 41.0 + i * 0.01, 60.0)];
      expect(BusinessPinLoader.capNearest(pins, 41.0, 60.0, cap: 20).length, 10);
      final capped = BusinessPinLoader.capNearest(pins, 41.0, 60.0, cap: 3);
      expect(capped.map((p) => p.id), ['p0', 'p1', 'p2']);
    });

    test('MapBounds.contains: чегара ичида ва четда', () {
      const b = MapBounds(south: 41, west: 60, north: 42, east: 61);
      expect(b.contains(41.5, 60.5), isTrue);
      expect(b.contains(41, 60), isTrue);
      expect(b.contains(40.99, 60.5), isFalse);
      expect(b.contains(41.5, 61.01), isFalse);
    });
  });

  group('mergeLinkedRestaurantPins (уланган объект + ресторан = битта белги, эга 2026-11-03)', () {
    BusinessPin biz(String id, {String rid = ''}) => BusinessPin.fromBusiness(Business(
          id: id, ownerId: '998901111111', name: id, category: BusinessCategory.food, phone: '998901111111',
          lat: 41.8, lng: 60.3, restaurantId: rid,
        ));
    BusinessPin rest(String id) => BusinessPin.fromRestaurant(
          Restaurant.fromMap(id, {'name': id, 'status': 'approved', 'lat': 41.8, 'lng': 60.3}),
        )!;
    List<String> keys(List<BusinessPin> pins) => [for (final p in pins) p.key];

    test('linkedRestaurantId: фақат объект манбасида ва уланган бўлса', () {
      expect(biz('b1', rid: 'r1').linkedRestaurantId, 'r1');
      expect(biz('b1').linkedRestaurantId, '');
      expect(rest('r1').linkedRestaurantId, '');
      expect(_pin('p', 1, 1).linkedRestaurantId, '', reason: 'origin йўқ');
    });

    test('уланган: ресторан белгиси олиб ташланади, объект белгиси қолади (битта белги)', () {
      final out = mergeLinkedRestaurantPins([rest('r1'), biz('b1', rid: 'r1')]);
      expect(keys(out), ['business:b1']);
    });

    test('уланмаган: иккаласи ҳам қолади; рўйхат ўзгармайди', () {
      final pins = [biz('b1'), rest('r1')];
      expect(identical(mergeLinkedRestaurantPins(pins), pins), isTrue);
      expect(keys(mergeLinkedRestaurantPins(pins)), ['business:b1', 'restaurant:r1']);
    });

    test('мос объекти рўйхатда йўқ ресторан қолади; бошқа ресторанга уланган объект ҳеч нарсани яширмайди', () {
      // b9 → r9 (r9 ҳудуддан ташқарида), r1 нинг объекти рўйхатда йўқ (блокланган/онлайн/ўқилмаган).
      final out = mergeLinkedRestaurantPins([biz('b9', rid: 'r9'), rest('r1')]);
      expect(keys(out), ['business:b9', 'restaurant:r1']);
    });

    test('бир нечта жуфт; бошқа манбалар ва бир хил ID ли бошқа манба тегилмайди; тартиб сақланади', () {
      final ws = BusinessPin(source: BusinessSource.wholesaleSeller, id: 'r2', name: 'w', category: BusinessCategory.retail, lat: 1, lng: 1);
      final out = mergeLinkedRestaurantPins([
        rest('r1'),
        biz('b1', rid: 'r1'),
        ws,
        rest('r2'),
        rest('r3'),
        biz('r3'), // объект ID'си ресторан ID'сига тенг, лекин уланмаган — ресторан қолади
        biz('b2', rid: 'r2'),
      ]);
      expect(keys(out), ['business:b1', 'wholesaleSeller:r2', 'restaurant:r3', 'business:r3', 'business:b2']);
    });

    test('бўш рўйхат — бўш', () {
      expect(mergeLinkedRestaurantPins(const []), isEmpty);
    });
  });
}
